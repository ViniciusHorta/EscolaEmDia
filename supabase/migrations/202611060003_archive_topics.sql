begin;

-- Arquivar temas.
-- Um tema que só existe em versões antigas de fichas não pode ser apagado (as versões publicadas são imutáveis).
-- Arquivar esconde-o da área dos pais (Edge Function «worksheets», /v1/topics) e do editor de fichas,
-- sem tocar no histórico. Só se arquiva um tema que nenhuma versão atual (mais recente ou publicada visível) usa,
-- para que nenhuma ficha visível aos pais fique com um tema escondido.
alter table public.topics add column archived_at timestamptz;

-- Arquivar (p_archived=true) ou reativar (false).
create function public.admin_set_topic_archived(p_id uuid, p_archived boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_topic public.topics;
begin
  select * into v_topic from public.topics where id = p_id for update;
  if not found then return jsonb_build_object('error', 'TOPIC_NOT_FOUND'); end if;
  if coalesce(p_archived, false) then
    -- Bloqueia se a versão mais recente ou a versão publicada mais recente de alguma ficha usa o tema.
    if exists(
      select 1 from public.worksheet_version_topics vt join public.worksheet_versions v on v.id = vt.worksheet_version_id
      where vt.topic_id = p_id and (
        v.version_number = (select max(o.version_number) from public.worksheet_versions o where o.worksheet_id = v.worksheet_id)
        or v.version_number = (select max(o.version_number) from public.worksheet_versions o
                               where o.worksheet_id = v.worksheet_id and o.published_at is not null))
    ) then
      return jsonb_build_object('error', 'TOPIC_IN_CURRENT_USE');
    end if;
    update public.topics set archived_at = coalesce(archived_at, now()) where id = p_id returning * into v_topic;
  else
    update public.topics set archived_at = null where id = p_id returning * into v_topic;
  end if;
  return jsonb_build_object('id', v_topic.id, 'archivedAt', v_topic.archived_at);
end;
$$;

-- Visão geral: igual a 202611060002, mais «archivedAt».
create or replace function public.admin_catalogue_overview()
returns jsonb language sql stable security definer set search_path = '' as $$
  with latest as (
    select distinct on (v.worksheet_id) v.worksheet_id, v.id as version_id
    from public.worksheet_versions v order by v.worksheet_id, v.version_number desc
  ), latest_published as (
    select distinct on (v.worksheet_id) v.worksheet_id, v.id as version_id
    from public.worksheet_versions v where v.published_at is not null order by v.worksheet_id, v.version_number desc
  ), usage as (
    select vt.topic_id, v.worksheet_id, v.id as version_id, v.version_number,
      exists(select 1 from latest l where l.version_id = v.id) as is_latest,
      exists(select 1 from latest_published lp where lp.version_id = v.id) as is_live,
      exists(select 1 from public.worksheet_assignments a where a.worksheet_version_id = v.id) as is_assigned
    from public.worksheet_version_topics vt join public.worksheet_versions v on v.id = vt.worksheet_version_id
  )
  select jsonb_build_object(
    'subjects', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name,
        'topicCount', (select count(*) from public.topics t where t.subject_id = s.id),
        'worksheetCount', (select count(*) from public.worksheets w where w.subject_id = s.id)
      ) order by s.name) from public.subjects s), '[]'::jsonb),
    'topics', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'subjectId', t.subject_id, 'schoolYear', t.school_year, 'name', t.name, 'archivedAt', t.archived_at,
        'worksheetCount', (select count(distinct u.worksheet_id) from usage u where u.topic_id = t.id and u.is_latest),
        'historyWorksheets', coalesce((select jsonb_agg(jsonb_build_object(
            'worksheetId', h.worksheet_id, 'versionNumbers', h.version_numbers, 'live', h.live, 'assigned', h.assigned))
          from (select u.worksheet_id, jsonb_agg(u.version_number order by u.version_number) as version_numbers,
                  bool_or(u.is_live) as live, bool_or(u.is_assigned) as assigned
                from usage u where u.topic_id = t.id
                  and not exists(select 1 from usage c where c.topic_id = t.id and c.worksheet_id = u.worksheet_id and c.is_latest)
                group by u.worksheet_id) h), '[]'::jsonb),
        'inUse', exists(select 1 from usage u where u.topic_id = t.id)
      ) order by t.school_year, t.name) from public.topics t), '[]'::jsonb)
  );
$$;

-- admin_save_worksheet: não permite ligar fichas a temas arquivados.
-- (Um tema arquivado nunca está na versão atual de uma ficha, por isso qualquer ligação seria nova.)
create or replace function public.admin_save_worksheet(
  p_worksheet_id uuid, p_subject_id uuid, p_school_year integer, p_topic_ids uuid[],
  p_title text, p_content jsonb, p_publish boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_topics uuid[];
  v_ws public.worksheets;
  v_latest public.worksheet_versions;
  v_version_id uuid;
  v_version_number integer;
  v_new_version boolean := false;
  v_published_now boolean := false;
begin
  if p_school_year is null or p_school_year not between 1 and 4 then return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR'); end if;
  if char_length(v_title) not between 1 and 160 then return jsonb_build_object('error', 'INVALID_TITLE'); end if;
  if p_content is null or not public.valid_worksheet_content(p_content) then return jsonb_build_object('error', 'INVALID_CONTENT'); end if;
  select coalesce(array_agg(distinct t order by t), '{}') into v_topics from unnest(coalesce(p_topic_ids, '{}'::uuid[])) t where t is not null;
  if cardinality(v_topics) = 0 then return jsonb_build_object('error', 'TOPICS_REQUIRED'); end if;
  if not exists(select 1 from public.subjects where id = p_subject_id) then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;

  if p_worksheet_id is not null then
    select * into v_ws from public.worksheets where id = p_worksheet_id for update;
    if not found then return jsonb_build_object('error', 'WORKSHEET_NOT_FOUND'); end if;
    if v_ws.subject_id <> p_subject_id and exists(select 1 from public.worksheet_versions
        where worksheet_id = v_ws.id and published_at is not null) then
      return jsonb_build_object('error', 'SUBJECT_LOCKED');
    end if;
  end if;

  if (select count(*) from public.topics where id = any(v_topics) and subject_id = p_subject_id
      and school_year = p_school_year) <> cardinality(v_topics) then
    return jsonb_build_object('error', 'TOPIC_MISMATCH');
  end if;
  if exists(select 1 from public.topics where id = any(v_topics) and archived_at is not null) then
    return jsonb_build_object('error', 'TOPIC_ARCHIVED');
  end if;

  if p_worksheet_id is null then
    insert into public.worksheets(subject_id, title) values (p_subject_id, v_title) returning * into v_ws;
    insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
      values (v_ws.id, 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
    insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
    v_new_version := true;
  else
    update public.worksheets set title = v_title, subject_id = p_subject_id where id = v_ws.id;
    select * into v_latest from public.worksheet_versions where worksheet_id = v_ws.id order by version_number desc limit 1 for update;
    if not found then
      insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
        values (v_ws.id, 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
      v_new_version := true;
    elsif v_latest.published_at is null then
      update public.worksheet_versions set content_json = p_content, school_year = p_school_year where id = v_latest.id;
      delete from public.worksheet_version_topics where worksheet_version_id = v_latest.id;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_latest.id, unnest(v_topics);
      v_version_id := v_latest.id; v_version_number := v_latest.version_number;
    elsif v_latest.content_json is distinct from p_content or v_latest.school_year <> p_school_year
      or (select coalesce(array_agg(topic_id order by topic_id), '{}') from public.worksheet_version_topics
          where worksheet_version_id = v_latest.id) is distinct from v_topics then
      insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
        values (v_ws.id, v_latest.version_number + 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
      v_new_version := true;
    else
      v_version_id := v_latest.id; v_version_number := v_latest.version_number;
    end if;
  end if;

  if coalesce(p_publish, false) then
    update public.worksheet_versions set published_at = now() where id = v_version_id and published_at is null;
    v_published_now := found;
    update public.worksheets set status = 'published' where id = v_ws.id;
  elsif not exists(select 1 from public.worksheet_versions where worksheet_id = v_ws.id and published_at is not null) then
    update public.worksheets set status = 'draft' where id = v_ws.id;
  end if;

  return jsonb_build_object('worksheetId', v_ws.id, 'versionId', v_version_id, 'versionNumber', v_version_number,
    'newVersion', v_new_version, 'publishedNow', v_published_now,
    'published', exists(select 1 from public.worksheet_versions where id = v_version_id and published_at is not null),
    'status', (select status from public.worksheets where id = v_ws.id));
end;
$$;

-- admin_import_worksheet (importador antigo): se o nome corresponde a um tema arquivado, recusa em vez de o reutilizar.
create or replace function public.admin_import_worksheet(
  p_subject_name text,
  p_school_year integer,
  p_topic_name text,
  p_title text,
  p_content jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_subject public.subjects;
  v_topic public.topics;
  v_topic_created boolean := false;
  v_title text := btrim(coalesce(p_title, ''));
  v_topic_name text := btrim(coalesce(p_topic_name, ''));
  v_existing record;
  v_worksheet_id uuid;
  v_version_id uuid;
begin
  if p_school_year is null or p_school_year not between 1 and 4 then
    return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR');
  end if;
  if char_length(v_title) not between 1 and 160 then
    return jsonb_build_object('error', 'INVALID_TITLE');
  end if;
  if char_length(v_topic_name) not between 1 and 120 then
    return jsonb_build_object('error', 'INVALID_TOPIC');
  end if;
  if p_content is null or not public.valid_worksheet_content(p_content) then
    return jsonb_build_object('error', 'INVALID_CONTENT');
  end if;

  select * into v_subject from public.subjects where lower(name) = lower(btrim(coalesce(p_subject_name, '')));
  if not found then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;

  select * into v_topic from public.topics
    where subject_id = v_subject.id and school_year = p_school_year and lower(name) = lower(v_topic_name);
  if found and v_topic.archived_at is not null then
    return jsonb_build_object('error', 'TOPIC_ARCHIVED');
  end if;
  if not found then
    insert into public.topics(subject_id, school_year, name) values (v_subject.id, p_school_year, v_topic_name)
      returning * into v_topic;
    v_topic_created := true;
  end if;

  select w.id as worksheet_id, v.id as version_id into v_existing
    from public.worksheets w join public.worksheet_versions v on v.worksheet_id = w.id
    where w.subject_id = v_subject.id and w.title = v_title and v.school_year = p_school_year
      and v.content_json = p_content
    limit 1;
  if found then
    return jsonb_build_object('duplicate', true, 'worksheetId', v_existing.worksheet_id,
      'versionId', v_existing.version_id, 'topicId', v_topic.id, 'topicCreated', v_topic_created);
  end if;

  insert into public.worksheets(subject_id, title) values (v_subject.id, v_title) returning id into v_worksheet_id;
  insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
    values (v_worksheet_id, 1, p_school_year, p_content) returning id into v_version_id;
  insert into public.worksheet_version_topics(worksheet_version_id, topic_id) values (v_version_id, v_topic.id);
  update public.worksheet_versions set published_at = now() where id = v_version_id;
  update public.worksheets set status = 'published' where id = v_worksheet_id;

  return jsonb_build_object('duplicate', false, 'worksheetId', v_worksheet_id, 'versionId', v_version_id,
    'topicId', v_topic.id, 'topicCreated', v_topic_created,
    'questionCount', jsonb_array_length(p_content->'questions'));
end;
$$;

revoke all on function public.admin_set_topic_archived(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_topic_archived(uuid, boolean) to service_role;
revoke all on function public.admin_catalogue_overview() from public, anon, authenticated;
grant execute on function public.admin_catalogue_overview() to service_role;
revoke all on function public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean) to service_role;
revoke all on function public.admin_import_worksheet(text, integer, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_import_worksheet(text, integer, text, text, jsonb) to service_role;

notify pgrst, 'reload schema';
commit;
