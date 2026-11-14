-- Fase 2 — Limites do plano Free e catálogo Free/Premium, aplicados no servidor.
--
-- Regras (valores em billing_settings):
--   * Fichas têm access_tier free|premium. Fichas Free têm no máximo free_max_questions questões,
--     validado ao publicar e ao marcar a ficha como Free. Reduzir o limite não invalida
--     fichas já publicadas (o admin mostra-as como "acima do limite").
--   * Dia comercial = dia civil em Europe/Lisbon.
--   * Responsável de criança Free: até free_daily_assignments fichas disponibilizadas por dia.
--     Uma ficha retirada que a criança não chegou a iniciar não conta.
--   * Criança Free: até free_daily_attempts tentativas iniciadas por dia (novas ou repetidas).
--     Retomar ou concluir uma tentativa em curso nunca é bloqueado.
--   * Criança Free só inicia fichas Free; criança locked não inicia nada novo.
--   * Premium: sem limites.
begin;

-- ---------------------------------------------------------------------------
-- Tier das fichas
-- ---------------------------------------------------------------------------
alter table public.worksheets add column access_tier text not null default 'premium'
  check (access_tier in ('free','premium'));
create index worksheets_access_tier_idx on public.worksheets(access_tier);

-- Fichas existentes: Free quando a versão mais recente cabe no limite; Premium caso contrário.
update public.worksheets w set access_tier = 'free'
 where (select jsonb_array_length(v.content_json->'questions') from public.worksheet_versions v
         where v.worksheet_id = w.id order by v.version_number desc limit 1)
       <= public.billing_setting('free_max_questions');

-- Publicar uma versão com demasiadas questões numa ficha Free é recusado.
create function public.guard_free_worksheet_version()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.published_at is not null and (tg_op = 'INSERT' or old.published_at is null)
     and exists (select 1 from public.worksheets where id = new.worksheet_id and access_tier = 'free')
     and jsonb_array_length(new.content_json->'questions') > public.billing_setting('free_max_questions') then
    raise exception using message = 'FREE_WORKSHEET_TOO_MANY_QUESTIONS', errcode = 'P0001',
      detail = format('Máximo de %s questões em fichas Free.', public.billing_setting('free_max_questions'));
  end if;
  return new;
end;
$$;
create trigger worksheet_versions_free_limit before insert or update on public.worksheet_versions
  for each row execute function public.guard_free_worksheet_version();

-- Marcar uma ficha como Free exige que a versão mais recente (publicada ou rascunho) caiba no limite.
create function public.guard_worksheet_access_tier()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.access_tier = 'free' and old.access_tier is distinct from 'free' and exists (
    select 1 from public.worksheet_versions v where v.worksheet_id = new.id
       and jsonb_array_length(v.content_json->'questions') > public.billing_setting('free_max_questions')
       and v.version_number = (select max(version_number) from public.worksheet_versions where worksheet_id = new.id)
  ) then
    raise exception using message = 'FREE_WORKSHEET_TOO_MANY_QUESTIONS', errcode = 'P0001',
      detail = format('Máximo de %s questões em fichas Free.', public.billing_setting('free_max_questions'));
  end if;
  return new;
end;
$$;
create trigger worksheets_access_tier_guard before update of access_tier on public.worksheets
  for each row execute function public.guard_worksheet_access_tier();

-- Catálogo visto pelos responsáveis: nova coluna access_tier (acrescentada no fim da view).
create or replace view public.worksheet_catalogue with (security_invoker=true) as
select v.id as version_id,w.id as worksheet_id,w.title,w.status as worksheet_status,w.is_sample,
  w.subject_id,s.name as subject_name,v.school_year,v.version_number,v.published_at,
  jsonb_array_length(v.content_json->'questions') as question_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type' in ('multiple-choice','true_false')) as choice_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type'='written') as written_count,
  array(select t.id from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_ids,
  array(select t.name from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_names,
  not exists(select 1 from public.worksheet_versions newer where newer.worksheet_id=w.id
    and newer.published_at is not null and newer.version_number>v.version_number) as is_latest,
  w.access_tier
from public.worksheet_versions v join public.worksheets w on w.id=v.worksheet_id
  join public.subjects s on s.id=w.subject_id where v.published_at is not null;

-- ---------------------------------------------------------------------------
-- Dia comercial e utilização diária
-- ---------------------------------------------------------------------------
create function public.billing_day_start()
returns timestamptz language sql stable set search_path = '' as $$
  select date_trunc('day', now() at time zone 'Europe/Lisbon') at time zone 'Europe/Lisbon';
$$;

create function public.child_assignments_today(p_child_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.worksheet_assignments a
   where a.child_id = p_child_id and a.assigned_at >= public.billing_day_start()
     and (a.status = 'active' or exists (select 1 from public.worksheet_attempts t where t.assignment_id = a.id));
$$;

create function public.child_attempts_today(p_child_id uuid)
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.worksheet_attempts t
   where t.child_id = p_child_id and t.started_at >= public.billing_day_start();
$$;

-- Plano + utilização do dia. Limites a null = ilimitado.
create function public.child_daily_access(p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb; v_free boolean;
begin
  v_access := public.child_access(p_child_id);
  v_free := v_access->>'plan' = 'free';
  return v_access || jsonb_build_object(
    'assignmentsToday', public.child_assignments_today(p_child_id),
    'assignmentLimit', case when v_free then public.billing_setting('free_daily_assignments') end,
    'attemptsToday', public.child_attempts_today(p_child_id),
    'attemptLimit', case when v_free then public.billing_setting('free_daily_attempts') end,
    'freeMaxQuestions', public.billing_setting('free_max_questions'),
    'catalogue', case when v_access->>'plan' = 'premium' then 'all' when v_free then 'free' else 'none' end
  );
end;
$$;

-- Devolve null quando permitido, ou {error, ...} pronto para a API.
create function public.billing_check_new_assignment(p_child_id uuid, p_version_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan text; v_tier text; v_limit integer;
begin
  v_plan := public.child_access(p_child_id)->>'plan';
  if v_plan = 'premium' then return null; end if;
  if v_plan = 'locked' then
    return jsonb_build_object('error','CHILD_PLAN_LOCKED','plan',v_plan);
  end if;
  select w.access_tier into v_tier from public.worksheet_versions v
    join public.worksheets w on w.id = v.worksheet_id where v.id = p_version_id;
  if v_tier is distinct from 'free' then
    return jsonb_build_object('error','PREMIUM_WORKSHEET_REQUIRED','plan',v_plan);
  end if;
  v_limit := public.billing_setting('free_daily_assignments');
  if public.child_assignments_today(p_child_id) >= v_limit then
    return jsonb_build_object('error','DAILY_ASSIGNMENT_LIMIT_REACHED','plan',v_plan,'limit',v_limit);
  end if;
  return null;
end;
$$;

create function public.billing_check_new_attempt(p_child_id uuid, p_version_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_plan text; v_tier text; v_limit integer;
begin
  v_plan := public.child_access(p_child_id)->>'plan';
  if v_plan = 'premium' then return null; end if;
  if v_plan = 'locked' then
    return jsonb_build_object('error','CHILD_PLAN_LOCKED');
  end if;
  select w.access_tier into v_tier from public.worksheet_versions v
    join public.worksheets w on w.id = v.worksheet_id where v.id = p_version_id;
  if v_tier is distinct from 'free' then
    return jsonb_build_object('error','PREMIUM_WORKSHEET_UNAVAILABLE');
  end if;
  v_limit := public.billing_setting('free_daily_attempts');
  if public.child_attempts_today(p_child_id) >= v_limit then
    return jsonb_build_object('error','DAILY_ATTEMPT_LIMIT_REACHED','limit',v_limit);
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atribuição (responsável): mesma função, com verificação do plano ao criar.
-- ---------------------------------------------------------------------------
create or replace function public.assign_worksheet_to_child(
  p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_child_id uuid,p_version_id uuid,p_request_id uuid,
  p_written_answer_mode text default 'typed'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb; v_child public.children; v_version public.worksheet_versions;
  v_assignment public.worksheet_assignments; v_family_id uuid; v_billing jsonb;
begin
  if p_written_answer_mode is null or p_written_answer_mode not in ('typed','paper') then
    return jsonb_build_object('error','INVALID_REQUEST');
  end if;
  v_access := public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
  if v_access ? 'error' then return v_access; end if;
  select family_id into v_family_id from public.children where id=p_child_id;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  perform 1 from public.families where id=v_family_id and status='active' for share;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  perform 1 from public.family_members where family_id=v_family_id and adult_user_id=p_actor_id and status='active' for share;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  select * into v_child from public.children where id=p_child_id for update;
  select * into v_assignment from public.worksheet_assignments where assigned_by=p_actor_id and client_request_id=p_request_id;
  if found then
    if v_assignment.child_id<>p_child_id or v_assignment.worksheet_version_id<>p_version_id
      or v_assignment.written_answer_mode<>p_written_answer_mode then
      return jsonb_build_object('error','REQUEST_CONFLICT');
    end if;
  else
    select v.* into v_version from public.worksheet_versions v join public.worksheets w on w.id=v.worksheet_id
      where v.id=p_version_id and v.published_at is not null and w.status='published' for share of v,w;
    if not found then return jsonb_build_object('error','WORKSHEET_NOT_FOUND'); end if;
    if v_version.school_year<>v_child.school_year then return jsonb_build_object('error','SCHOOL_YEAR_MISMATCH'); end if;
    if exists(select 1 from public.worksheet_assignments where child_id=p_child_id and worksheet_version_id=p_version_id and status='active') then
      return jsonb_build_object('error','ASSIGNMENT_ALREADY_ACTIVE');
    end if;
    -- Plano: a linha da criança já está bloqueada (for update), o que serializa a contagem diária.
    v_billing := public.billing_check_new_assignment(p_child_id,p_version_id);
    if v_billing is not null then return v_billing; end if;
    insert into public.worksheet_assignments(child_id,worksheet_version_id,assigned_by,client_request_id,written_answer_mode)
      values(p_child_id,p_version_id,p_actor_id,p_request_id,p_written_answer_mode) returning * into v_assignment;
    insert into public.family_audit_events(family_id,actor_id,event_type,payload)
      values(v_family_id,p_actor_id,'worksheet.assigned',jsonb_build_object('assignmentId',v_assignment.id,'childId',p_child_id,
        'worksheetVersionId',p_version_id,'writtenAnswerMode',p_written_answer_mode));
  end if;
  return jsonb_build_object('id',v_assignment.id,'childId',v_assignment.child_id,'worksheetVersionId',v_assignment.worksheet_version_id,
    'assignedAt',v_assignment.assigned_at,'status',v_assignment.status,'writtenAnswerMode',v_assignment.written_answer_mode);
end;
$$;

-- ---------------------------------------------------------------------------
-- Início de tentativa (criança): verificação só quando é criada uma tentativa nova.
-- ---------------------------------------------------------------------------
create or replace function public.start_child_attempt(p_token_hash text,p_assignment_id uuid,p_request_id uuid,p_request_hash text,
 p_previous_attempt_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_child_id uuid;v_assignment public.worksheet_assignments;
 v_attempt public.worksheet_attempts;v_previous public.worksheet_attempts;v_latest public.worksheet_attempts;
 v_operation public.sync_operations;v_created boolean:=false;v_family_id uuid;v_billing jsonb;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 v_child_id:=(v_session->'child'->>'id')::uuid;
 if p_request_id is null or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('error','INVALID_REQUEST');end if;
 -- Serializes first starts and repetitions; answer saves/submission already lock this assignment.
 select * into v_assignment from public.worksheet_assignments where id=p_assignment_id and child_id=v_child_id for update;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 select * into v_operation from public.sync_operations where id=p_request_id;
 if found then
  if v_operation.operation_type<>'start_attempt' or v_operation.request_hash<>p_request_hash
    or not exists(select 1 from public.worksheet_attempts where id=v_operation.attempt_id and child_id=v_child_id and assignment_id=p_assignment_id) then
   return jsonb_build_object('error','OPERATION_REUSED');end if;
  return public.child_attempt_payload(v_operation.attempt_id);
 end if;
 if v_assignment.status<>'active' then return jsonb_build_object('error','ASSIGNMENT_WITHDRAWN');end if;
 select * into v_latest from public.worksheet_attempts where assignment_id=p_assignment_id order by attempt_number desc limit 1;
 select * into v_attempt from public.worksheet_attempts where assignment_id=p_assignment_id and status='in_progress';
 if p_previous_attempt_id is not null then
  select * into v_previous from public.worksheet_attempts where id=p_previous_attempt_id and assignment_id=p_assignment_id and child_id=v_child_id;
  if not found or v_previous.status<>'completed' then return jsonb_build_object('error','REPEAT_NOT_AVAILABLE');end if;
  -- A second device joins the current attempt instead of creating a parallel one.
  if v_attempt.id is null and v_latest.id is distinct from p_previous_attempt_id then
   return jsonb_build_object('error','REPEAT_STATE_CHANGED');end if;
 elsif v_attempt.id is null and v_latest.id is not null then
  -- An outdated first-start screen must never create an unintended repetition.
  v_attempt:=v_latest;
 end if;
 if v_attempt.id is null then
  -- Plano: serializa as tentativas da criança (várias fichas em paralelo) e verifica o limite diário.
  perform 1 from public.children where id=v_child_id for update;
  v_billing:=public.billing_check_new_attempt(v_child_id,v_assignment.worksheet_version_id);
  if v_billing is not null then return v_billing;end if;
  insert into public.worksheet_attempts(assignment_id,child_id,worksheet_version_id,attempt_number,started_at)
   values(p_assignment_id,v_child_id,v_assignment.worksheet_version_id,coalesce(v_latest.attempt_number,0)+1,clock_timestamp())
   returning * into v_attempt;
  v_created:=true;
 end if;
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_request_id,v_attempt.id,'start_attempt',p_request_hash,jsonb_build_object('attemptId',v_attempt.id));
 if v_created then
  select family_id into v_family_id from public.children where id=v_child_id;
  insert into public.family_audit_events(family_id,event_type,payload)
   values(v_family_id,case when p_previous_attempt_id is null then 'attempt.started' else 'attempt.repeated' end,
    jsonb_build_object('actorType','child','childId',v_child_id,'assignmentId',p_assignment_id,'attemptId',v_attempt.id,
     'attemptNumber',v_attempt.attempt_number,'previousAttemptId',p_previous_attempt_id));
 end if;
 -- No answer/review copying: a newly inserted attempt has its own empty answer set.
 return public.child_attempt_payload(v_attempt.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------
create function public.admin_set_worksheet_tier(p_id uuid, p_tier text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_tier text;
begin
  if p_tier is null or p_tier not in ('free','premium') then
    raise exception using message = 'INVALID_TIER', errcode = 'P0001';
  end if;
  update public.worksheets set access_tier = p_tier where id = p_id returning access_tier into v_tier;
  if not found then
    raise exception using message = 'WORKSHEET_NOT_FOUND', errcode = 'P0001';
  end if;
  return jsonb_build_object('id', p_id, 'accessTier', v_tier);
end;
$$;

-- Listagem do admin: + accessTier e exceedsFreeLimit (fichas Free acima do limite atual).
create or replace function public.admin_list_worksheets()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb) from (
    select w.created_at, jsonb_build_object(
      'id', w.id, 'title', w.title, 'status', w.status, 'isSample', w.is_sample, 'createdAt', w.created_at,
      'subjectId', w.subject_id, 'subjectName', s.name,
      'accessTier', w.access_tier,
      'exceedsFreeLimit', w.access_tier = 'free' and coalesce((select jsonb_array_length(v.content_json->'questions')
          from public.worksheet_versions v where v.worksheet_id = w.id order by v.version_number desc limit 1), 0)
          > public.billing_setting('free_max_questions'),
      'versionCount', (select count(*) from public.worksheet_versions v where v.worksheet_id = w.id),
      'publishedVersionCount', (select count(*) from public.worksheet_versions v where v.worksheet_id = w.id and v.published_at is not null),
      'latest', (select jsonb_build_object(
          'versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year, 'publishedAt', v.published_at,
          'questionCount', jsonb_array_length(v.content_json->'questions'),
          'choiceCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'multiple-choice'),
          'trueFalseCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'true_false'),
          'writtenCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'written'),
          'topicIds', coalesce((select jsonb_agg(vt.topic_id) from public.worksheet_version_topics vt where vt.worksheet_version_id = v.id), '[]'::jsonb))
        from public.worksheet_versions v where v.worksheet_id = w.id order by v.version_number desc limit 1),
      'assignmentCount', (select count(*) from public.worksheet_assignments a
          join public.worksheet_versions v on v.id = a.worksheet_version_id where v.worksheet_id = w.id),
      'openReportCount', (select count(*) from public.question_reports r
          join public.worksheet_versions v on v.id = r.worksheet_version_id where v.worksheet_id = w.id and r.status in ('open','in_review'))
    ) as item
    from public.worksheets w join public.subjects s on s.id = w.subject_id
  ) x;
$$;

create or replace function public.admin_get_worksheet(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', w.id, 'title', w.title, 'status', w.status, 'isSample', w.is_sample, 'subjectId', w.subject_id,
    'accessTier', w.access_tier,
    'freeMaxQuestions', public.billing_setting('free_max_questions'),
    'versions', coalesce((select jsonb_agg(jsonb_build_object(
        'versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year, 'publishedAt', v.published_at,
        'questionCount', jsonb_array_length(v.content_json->'questions')) order by v.version_number desc)
      from public.worksheet_versions v where v.worksheet_id = w.id), '[]'::jsonb),
    'latest', (select jsonb_build_object('versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year,
        'publishedAt', v.published_at, 'content', v.content_json,
        'topicIds', coalesce((select jsonb_agg(vt.topic_id) from public.worksheet_version_topics vt where vt.worksheet_version_id = v.id), '[]'::jsonb))
      from public.worksheet_versions v where v.worksheet_id = w.id order by v.version_number desc limit 1)
  ) from public.worksheets w where w.id = p_id;
$$;

-- ---------------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------------
revoke all on function
  public.guard_free_worksheet_version(), public.guard_worksheet_access_tier(), public.billing_day_start(),
  public.child_assignments_today(uuid), public.child_attempts_today(uuid), public.child_daily_access(uuid),
  public.billing_check_new_assignment(uuid,uuid), public.billing_check_new_attempt(uuid,uuid),
  public.admin_set_worksheet_tier(uuid,text)
  from public, anon, authenticated;
grant execute on function public.child_daily_access(uuid), public.admin_set_worksheet_tier(uuid,text) to service_role;

notify pgrst, 'reload schema';
commit;
