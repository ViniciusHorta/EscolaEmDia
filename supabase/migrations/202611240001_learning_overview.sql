begin;

-- Visão de Aprendizagem (PRD v1.0). Devolve só contagens por eixo (disciplina ou tema);
-- índice de prática, desempenho, estados e sugestões são calculados na app.
--
-- Regras aplicadas aqui:
--  * Só tentativas entregues (submitted, pending_review, completed), pela data de entrega (HP09).
--  * Prática: todas as tentativas do período, cada pergunta conta como um exercício.
--  * Desempenho: só a tentativa entregue mais recente de cada ficha no período.
--  * Escolha múltipla / V-F: certa ou incorreta (sem resposta = incorreta, HP11).
--  * Resposta escrita: classificação da revisão; respondida sem revisão = pendente; sem resposta = incorreta.
--  * Ano escolar: desde 1 de setembro (Europe/Lisbon), sem período anterior (HP12).
--  * Gratuito: só 30 dias e só por disciplina; sem período anterior (evolução é Premium).

create function public.learning_period_bounds(p_period text, p_now timestamptz default now())
returns table(cur_from timestamptz, cur_to timestamptz, prev_from timestamptz)
language sql stable set search_path = '' as $$
  with lx as (select (p_now at time zone 'Europe/Lisbon') as local_now)
  select
    case p_period
      when '7d' then p_now - interval '7 days'
      when '30d' then p_now - interval '30 days'
      when '90d' then p_now - interval '90 days'
      else make_date(extract(year from lx.local_now)::int - case when extract(month from lx.local_now) < 9 then 1 else 0 end, 9, 1)::timestamp
             at time zone 'Europe/Lisbon'
    end,
    p_now,
    case p_period
      when '7d' then p_now - interval '14 days'
      when '30d' then p_now - interval '60 days'
      when '90d' then p_now - interval '180 days'
    end
  from lx;
$$;
revoke all on function public.learning_period_bounds(text, timestamptz) from public, anon, authenticated;

create function public.get_parent_child_learning(p_actor_id uuid, p_auth_session_id uuid, p_unlock_hash text,
  p_child_id uuid, p_period text default '30d', p_subject_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_access jsonb; v_child public.children; v_plan text; v_subject public.subjects;
  v_from timestamptz; v_to timestamptz; v_prev timestamptz; v_axes jsonb; v_completed integer;
begin
  if p_period is null or p_period not in ('7d','30d','90d','year') then
    return jsonb_build_object('error','INVALID_REQUEST');
  end if;
  v_access := public.use_parent_unlock(p_actor_id, p_auth_session_id, p_unlock_hash, true, false);
  if v_access ? 'error' then return v_access; end if;
  select c.* into v_child from public.children c join public.families f on f.id = c.family_id
    join public.family_members m on m.family_id = f.id
   where c.id = p_child_id and f.status = 'active' and m.adult_user_id = p_actor_id and m.status = 'active';
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;

  v_plan := coalesce(public.child_access(p_child_id)->>'plan', 'free');
  if v_plan <> 'premium' and (p_period <> '30d' or p_subject_id is not null) then
    return jsonb_build_object('error','PREMIUM_REQUIRED');
  end if;
  if p_subject_id is not null then
    select * into v_subject from public.subjects where id = p_subject_id;
    if not found then return jsonb_build_object('error','INVALID_REQUEST'); end if;
  end if;

  select b.cur_from, b.cur_to, b.prev_from into v_from, v_to, v_prev from public.learning_period_bounds(p_period) b;
  if v_plan <> 'premium' then v_prev := null; end if;

  with attempts as materialized (
    select a.id, a.worksheet_version_id as version_id, v.worksheet_id, w.subject_id, v.content_json,
      a.submitted_at >= v_from as is_current,
      row_number() over (partition by v.worksheet_id, a.submitted_at >= v_from
                         order by a.submitted_at desc, a.id desc) = 1 as is_latest
    from public.worksheet_attempts a
    join public.worksheet_versions v on v.id = a.worksheet_version_id
    join public.worksheets w on w.id = v.worksheet_id
    where a.child_id = p_child_id
      and a.status in ('submitted','pending_review','completed')
      and a.submitted_at < v_to and a.submitted_at >= coalesce(v_prev, v_from)
      and (p_subject_id is null or w.subject_id = p_subject_id)
  ), questions as (
    select t.id as attempt_id, t.version_id, t.subject_id, t.is_current, t.is_latest,
      case
        when q.value->>'type' in ('multiple-choice','true_false') then
          case when (case a.answer_type when 'true_false' then a.value_json->>'value'
                                         when 'multiple-choice' then a.value_json->>'selectedOptionId' end)
                    = q.value->>'correctAnswer' then 'correct' else 'incorrect' end
        when r.classification = 'correct' then 'correct'
        when r.classification = 'partially_correct' then 'partial'
        when r.classification = 'incorrect' then 'incorrect'
        when a.answer_type = 'paper' or (a.answer_type = 'typed'
          and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g')) > 0) then 'pending'
        else 'incorrect'
      end as result
    from attempts t
    cross join lateral jsonb_array_elements(t.content_json->'questions') q(value)
    left join public.answers a on a.attempt_id = t.id and a.question_id = q.value->>'id'
    left join public.answer_reviews r on r.answer_id = a.id
  ), keyed as (
    select q.*, q.subject_id as axis_id from questions q where p_subject_id is null
    union all
    select q.*, vt.topic_id from questions q
      join public.worksheet_version_topics vt on vt.worksheet_version_id = q.version_id
     where p_subject_id is not null
  ), stats as (
    select axis_id,
      count(distinct attempt_id) filter (where is_current)::integer as attempts,
      count(*) filter (where is_current)::integer as exercises,
      count(*) filter (where is_current and is_latest and result = 'correct')::integer as correct,
      count(*) filter (where is_current and is_latest and result = 'partial')::integer as partial,
      count(*) filter (where is_current and is_latest and result = 'incorrect')::integer as incorrect,
      count(*) filter (where is_current and result = 'pending')::integer as pending,
      count(*) filter (where not is_current and is_latest and result = 'correct')::integer as prev_correct,
      count(*) filter (where not is_current and is_latest and result = 'partial')::integer as prev_partial,
      count(*) filter (where not is_current and is_latest and result = 'incorrect')::integer as prev_incorrect
    from keyed group by axis_id
  ), axes as (
    -- Disciplinas do ano da criança (com fichas publicadas) + qualquer outra com atividade.
    select s.id, s.name from public.subjects s
     where p_subject_id is null and (
       s.id in (select w.subject_id from public.worksheets w join public.worksheet_versions v on v.worksheet_id = w.id
                 where w.status = 'published' and v.published_at is not null and v.school_year = v_child.school_year)
       or s.id in (select axis_id from stats))
    union all
    -- Temas da disciplina no ano da criança (com fichas publicadas) + temas praticados (HP03: todos).
    select t.id, t.name from public.topics t
     where p_subject_id is not null and t.subject_id = p_subject_id and (
       (t.school_year = v_child.school_year and t.archived_at is null and exists (
          select 1 from public.worksheet_version_topics vt join public.worksheet_versions v on v.id = vt.worksheet_version_id
            join public.worksheets w on w.id = v.worksheet_id
           where vt.topic_id = t.id and v.published_at is not null and w.status = 'published'))
       or t.id in (select axis_id from stats))
  )
  select
    coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name,
      'attempts', coalesce(st.attempts, 0), 'exercises', coalesce(st.exercises, 0),
      'correct', coalesce(st.correct, 0), 'partial', coalesce(st.partial, 0),
      'incorrect', coalesce(st.incorrect, 0), 'pending', coalesce(st.pending, 0),
      'previous', case when v_prev is null then null else jsonb_build_object(
        'correct', coalesce(st.prev_correct, 0), 'partial', coalesce(st.prev_partial, 0),
        'incorrect', coalesce(st.prev_incorrect, 0)) end)
      order by x.name, x.id), '[]'::jsonb),
    (select count(distinct attempt_id)::integer from questions where is_current)
  into v_axes, v_completed
  from axes x left join stats st on st.axis_id = x.id;

  return jsonb_build_object(
    'child', jsonb_build_object('id', v_child.id, 'familyId', v_child.family_id, 'displayName', v_child.display_name,
      'schoolYear', v_child.school_year, 'avatarId', v_child.avatar_id),
    'plan', v_plan, 'period', p_period, 'from', v_from, 'to', v_to, 'previousFrom', v_prev,
    'subject', case when p_subject_id is null then null else jsonb_build_object('id', v_subject.id, 'name', v_subject.name) end,
    'completedAttempts', coalesce(v_completed, 0),
    'axes', v_axes);
end;
$$;
revoke all on function public.get_parent_child_learning(uuid,uuid,text,uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.get_parent_child_learning(uuid,uuid,text,uuid,text,uuid) to service_role;

notify pgrst, 'reload schema';
commit;
