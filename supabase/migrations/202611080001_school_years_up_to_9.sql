begin;

-- Todo o ensino básico: os anos escolares válidos passam de 1–4 (1.º ciclo) para 1–9
-- (2.º ciclo: 5.º–6.º; 3.º ciclo: 7.º–9.º). Alarga os CHECK das tabelas e redefine as
-- funções que validavam explicitamente o intervalo (corpo igual às versões anteriores,
-- só muda o limite).

alter table public.children drop constraint if exists children_school_year_check;
alter table public.children add constraint children_school_year_check check (school_year between 1 and 9);

alter table public.topics drop constraint if exists topics_school_year_check;
alter table public.topics add constraint topics_school_year_check check (school_year between 1 and 9);

alter table public.worksheet_versions drop constraint if exists worksheet_versions_school_year_check;
alter table public.worksheet_versions add constraint worksheet_versions_school_year_check check (school_year between 1 and 9);

-- update_child_profile (base: 202611060005)
create or replace function public.update_child_profile(
  p_actor_id uuid, p_family_id uuid, p_child_id uuid, p_display_name text,
  p_school_year integer, p_avatar_id text, p_pin_hash text default null, p_salt text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_before public.children;
  v_child public.children;
  v_changed text[] := array[]::text[];
begin
  if not exists (select 1 from auth.users where id = p_actor_id and email_confirmed_at is not null) then
    raise exception using message = 'AUTH_REQUIRED', errcode = 'P0001';
  end if;
  perform 1 from public.families where id = p_family_id and status = 'active' for share;
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  perform 1 from public.family_members where family_id = p_family_id
    and adult_user_id = p_actor_id and status = 'active' for share;
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  if p_display_name is null or char_length(btrim(p_display_name)) not between 1 and 40
    or p_school_year is null or p_school_year not between 1 and 9
    or p_avatar_id is null or p_avatar_id not in ('fox','owl','bear','lynx','dolphin','rabbit')
    or (p_pin_hash is null) <> (p_salt is null)
    or (p_pin_hash is not null and (p_pin_hash !~ '^[0-9a-f]{64}$' or p_salt !~ '^[0-9a-f]{32}$')) then
    raise exception using message = 'INVALID_PROFILE', errcode = 'P0001';
  end if;

  select * into v_before from public.children
    where id = p_child_id and family_id = p_family_id for update;
  if not found then
    raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
  end if;

  update public.children set display_name = btrim(p_display_name),
    school_year = p_school_year, avatar_id = p_avatar_id
    where id = p_child_id returning * into v_child;
  if v_before.display_name is distinct from v_child.display_name then v_changed := array_append(v_changed, 'displayName'); end if;
  if v_before.school_year is distinct from v_child.school_year then v_changed := array_append(v_changed, 'schoolYear'); end if;
  if v_before.avatar_id is distinct from v_child.avatar_id then v_changed := array_append(v_changed, 'avatarId'); end if;

  if p_pin_hash is not null then
    -- clock_timestamp garante uma versão de credencial diferente da anterior.
    update public.child_pin_credentials set pin_hash = p_pin_hash, salt = p_salt,
      updated_at = clock_timestamp()
      where child_id = p_child_id;
    if not found then
      raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
    end if;
    update public.child_pin_attempts set attempt_count = 0, blocked_until = null,
      window_started_at = now(), challenge_id = null, challenge_expires_at = null
      where child_id = p_child_id;
    update public.child_sessions set revoked_at = now()
      where child_id = p_child_id and revoked_at is null;
    v_changed := array_append(v_changed, 'pin');
  end if;

  if cardinality(v_changed) > 0 then
    insert into public.family_audit_events(family_id, actor_id, event_type, payload)
      values (p_family_id, p_actor_id, 'child.updated',
        jsonb_build_object('childId', p_child_id, 'fields', to_jsonb(v_changed)));
  end if;

  return jsonb_build_object('id',v_child.id,'familyId',v_child.family_id,
    'displayName',v_child.display_name,'schoolYear',v_child.school_year,
    'avatarId',v_child.avatar_id,'createdAt',v_child.created_at);
end;
$$;

-- admin_save_topic (base: 202611060001)
create or replace function public.admin_save_topic(p_id uuid, p_subject_id uuid, p_school_year integer, p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_name text := btrim(coalesce(p_name, '')); v_topic public.topics;
begin
  if char_length(v_name) not between 1 and 120 then return jsonb_build_object('error', 'INVALID_NAME'); end if;
  if p_school_year is null or p_school_year not between 1 and 9 then return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR'); end if;
  if not exists(select 1 from public.subjects where id = p_subject_id) then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;
  if exists(select 1 from public.topics where subject_id = p_subject_id and school_year = p_school_year
      and lower(name) = lower(v_name) and id is distinct from p_id) then
    return jsonb_build_object('error', 'TOPIC_EXISTS');
  end if;
  if p_id is null then
    insert into public.topics(subject_id, school_year, name) values (p_subject_id, p_school_year, v_name) returning * into v_topic;
  else
    select * into v_topic from public.topics where id = p_id for update;
    if not found then return jsonb_build_object('error', 'TOPIC_NOT_FOUND'); end if;
    -- Um tema já usado por fichas só pode ser renomeado (as versões publicadas dependem da disciplina e do ano).
    if (v_topic.subject_id <> p_subject_id or v_topic.school_year <> p_school_year)
      and exists(select 1 from public.worksheet_version_topics where topic_id = p_id) then
      return jsonb_build_object('error', 'TOPIC_IN_USE');
    end if;
    update public.topics set subject_id = p_subject_id, school_year = p_school_year, name = v_name
      where id = p_id returning * into v_topic;
  end if;
  return jsonb_build_object('id', v_topic.id, 'subjectId', v_topic.subject_id, 'schoolYear', v_topic.school_year, 'name', v_topic.name);
end;
$$;

-- admin_save_worksheet e admin_import_worksheet (base: 202611060003)
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
  if p_school_year is null or p_school_year not between 1 and 9 then return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR'); end if;
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
  if p_school_year is null or p_school_year not between 1 and 9 then
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

revoke all on function public.update_child_profile(uuid,uuid,uuid,text,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.update_child_profile(uuid,uuid,uuid,text,integer,text,text,text) to service_role;
revoke all on function public.admin_save_topic(uuid, uuid, integer, text) from public, anon, authenticated;
grant execute on function public.admin_save_topic(uuid, uuid, integer, text) to service_role;
revoke all on function public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean) to service_role;
revoke all on function public.admin_import_worksheet(text, integer, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.admin_import_worksheet(text, integer, text, text, jsonb) to service_role;

notify pgrst, 'reload schema';
commit;
