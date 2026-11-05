begin;
create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(btrim(name)) between 1 and 80)
);
create table public.topics (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id),
  school_year smallint not null check (school_year between 1 and 4),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  unique(subject_id,school_year,name)
);
create table public.worksheets (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  is_sample boolean not null default false,
  created_at timestamptz not null default now()
);

-- Validate the initial supported question formats without creating per-question tables.
create function public.valid_worksheet_content(p_content jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare q jsonb; o jsonb; ids text[] := '{}'; option_ids text[];
begin
  if jsonb_typeof(p_content) is distinct from 'object'
    or jsonb_typeof(p_content->'questions') is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_content->'questions') not between 1 and 50 then return false; end if;
  for q in select value from jsonb_array_elements(p_content->'questions') loop
    if jsonb_typeof(q) is distinct from 'object' or jsonb_typeof(q->'id') is distinct from 'string'
      or coalesce(btrim(q->>'id'),'')='' or (q->>'id')=any(ids)
      or jsonb_typeof(q->'prompt') is distinct from 'string' or coalesce(btrim(q->>'prompt'),'')=''
      or coalesce(q->>'type','') not in ('multiple-choice','written') then return false; end if;
    ids := array_append(ids,q->>'id');
    if q->>'type'='multiple-choice' then
      if jsonb_typeof(q->'options') is distinct from 'array' then return false; end if;
      if jsonb_array_length(q->'options') not between 2 and 8 then return false; end if;
      option_ids := '{}';
      for o in select value from jsonb_array_elements(q->'options') loop
        if jsonb_typeof(o) is distinct from 'object' or jsonb_typeof(o->'id') is distinct from 'string'
          or coalesce(btrim(o->>'id'),'')='' or (o->>'id')=any(option_ids)
          or jsonb_typeof(o->'text') is distinct from 'string' or coalesce(btrim(o->>'text'),'')='' then return false; end if;
        option_ids := array_append(option_ids,o->>'id');
      end loop;
      if jsonb_typeof(q->'correctAnswer') is distinct from 'string'
        or not coalesce((q->>'correctAnswer')=any(option_ids),false) then return false; end if;
    end if;
  end loop;
  return true;
end;
$$;
revoke all on function public.valid_worksheet_content(jsonb) from public,anon,authenticated;

create table public.worksheet_versions (
  id uuid primary key default gen_random_uuid(),
  worksheet_id uuid not null references public.worksheets(id),
  version_number integer not null check (version_number>0),
  school_year smallint not null check (school_year between 1 and 4),
  content_json jsonb not null check (public.valid_worksheet_content(content_json)),
  published_at timestamptz,
  unique(worksheet_id,version_number)
);
create table public.worksheet_version_topics (
  worksheet_version_id uuid not null references public.worksheet_versions(id),
  topic_id uuid not null references public.topics(id),
  primary key(worksheet_version_id,topic_id)
);
create index worksheet_version_topics_topic_idx on public.worksheet_version_topics(topic_id,worksheet_version_id);

create function public.guard_worksheet_version()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    if old.published_at is not null then raise exception 'PUBLISHED_VERSION_IMMUTABLE'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  if new.published_at is not null then
    if not exists(select 1 from public.worksheet_version_topics where worksheet_version_id=new.id) then
      raise exception 'PUBLISHED_VERSION_NEEDS_TOPICS';
    end if;
    if exists(select 1 from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
      join public.worksheets w on w.id=new.worksheet_id where vt.worksheet_version_id=new.id
        and (t.subject_id<>w.subject_id or t.school_year<>new.school_year)) then
      raise exception 'VERSION_TOPIC_MISMATCH';
    end if;
  end if;
  return new;
end;
$$;
create trigger worksheet_versions_immutable before insert or update or delete on public.worksheet_versions
  for each row execute function public.guard_worksheet_version();
create function public.guard_worksheet_version_topics()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op in ('UPDATE','DELETE') then
    if exists(select 1 from public.worksheet_versions where id=old.worksheet_version_id and published_at is not null) then
      raise exception 'PUBLISHED_VERSION_IMMUTABLE';
    end if;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    if exists(select 1 from public.worksheet_versions where id=new.worksheet_version_id and published_at is not null) then
      raise exception 'PUBLISHED_VERSION_IMMUTABLE';
    end if;
    return new;
  end if;
  return old;
end;
$$;
create trigger worksheet_topics_immutable before insert or update or delete on public.worksheet_version_topics
  for each row execute function public.guard_worksheet_version_topics();
revoke all on function public.guard_worksheet_version(), public.guard_worksheet_version_topics() from public,anon,authenticated;

create table public.worksheet_assignments (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children(id),
  worksheet_version_id uuid not null references public.worksheet_versions(id),
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active','withdrawn')),
  client_request_id uuid not null,
  unique(assigned_by,client_request_id)
);
create unique index worksheet_assignments_active_unique on public.worksheet_assignments(child_id,worksheet_version_id) where status='active';
create index worksheet_assignments_child_status_date_idx on public.worksheet_assignments(child_id,status,assigned_at);

-- Metadata only. Solutions remain in content_json, never in this view.
create view public.worksheet_catalogue with (security_invoker=true) as
select v.id as version_id,w.id as worksheet_id,w.title,w.status as worksheet_status,w.is_sample,
  w.subject_id,s.name as subject_name,v.school_year,v.version_number,v.published_at,
  jsonb_array_length(v.content_json->'questions') as question_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type'='multiple-choice') as choice_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type'='written') as written_count,
  array(select t.id from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_ids,
  array(select t.name from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_names,
  not exists(select 1 from public.worksheet_versions newer where newer.worksheet_id=w.id
    and newer.published_at is not null and newer.version_number>v.version_number) as is_latest
from public.worksheet_versions v join public.worksheets w on w.id=v.worksheet_id
  join public.subjects s on s.id=w.subject_id where v.published_at is not null;

alter table public.subjects enable row level security;
alter table public.topics enable row level security;
alter table public.worksheets enable row level security;
alter table public.worksheet_versions enable row level security;
alter table public.worksheet_version_topics enable row level security;
alter table public.worksheet_assignments enable row level security;
revoke all on public.subjects,public.topics,public.worksheets,public.worksheet_versions,
  public.worksheet_version_topics,public.worksheet_assignments,public.worksheet_catalogue from public,anon,authenticated,service_role;
grant select on public.subjects,public.topics,public.worksheets,public.worksheet_versions,
  public.worksheet_version_topics,public.worksheet_assignments,public.worksheet_catalogue to service_role;

create function public.assign_worksheet_to_child(
  p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_child_id uuid,p_version_id uuid,p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb; v_child public.children; v_version public.worksheet_versions;
  v_assignment public.worksheet_assignments; v_family_id uuid;
begin
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
    if v_assignment.child_id<>p_child_id or v_assignment.worksheet_version_id<>p_version_id then
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
    insert into public.worksheet_assignments(child_id,worksheet_version_id,assigned_by,client_request_id)
      values(p_child_id,p_version_id,p_actor_id,p_request_id) returning * into v_assignment;
    insert into public.family_audit_events(family_id,actor_id,event_type,payload)
      values(v_family_id,p_actor_id,'worksheet.assigned',jsonb_build_object('assignmentId',v_assignment.id,'childId',p_child_id,'worksheetVersionId',p_version_id));
  end if;
  return jsonb_build_object('id',v_assignment.id,'childId',v_assignment.child_id,'worksheetVersionId',v_assignment.worksheet_version_id,
    'assignedAt',v_assignment.assigned_at,'status',v_assignment.status);
end;
$$;
revoke all on function public.assign_worksheet_to_child(uuid,uuid,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_worksheet_to_child(uuid,uuid,text,uuid,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
