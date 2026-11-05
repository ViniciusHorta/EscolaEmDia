begin;

create table public.families (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  recovery_deadline_at timestamptz,
  created_by uuid not null references auth.users(id),
  creation_request_id uuid not null,
  unique (created_by, creation_request_id)
);
create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  adult_user_id uuid not null references auth.users(id),
  status text not null default 'active' check (status in ('active', 'left', 'removed')),
  joined_at timestamptz not null default now(),
  unique (family_id, adult_user_id)
);
create index family_members_adult_status_idx on public.family_members(adult_user_id, status);
create table public.children (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
  school_year smallint not null check (school_year between 1 and 4),
  avatar_id text not null check (avatar_id in ('fox','owl','bear','lynx','dolphin','rabbit')),
  created_at timestamptz not null default now()
);
create index children_family_idx on public.children(family_id);
create table public.child_pin_credentials (
  child_id uuid primary key references public.children(id) on delete cascade,
  pin_hash text not null check (pin_hash ~ '^[0-9a-f]{64}$'),
  salt text not null check (salt ~ '^[0-9a-f]{32}$'),
  algorithm text not null default 'pbkdf2-sha256-hmac-pepper-v1'
    check (algorithm = 'pbkdf2-sha256-hmac-pepper-v1'),
  iterations integer not null check (iterations = 600000),
  updated_at timestamptz not null default now(),
  creation_fingerprint text not null check (creation_fingerprint ~ '^[0-9a-f]{64}$')
);
create table public.family_audit_events (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index family_audit_events_family_created_idx on public.family_audit_events(family_id, created_at);

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.children enable row level security;
alter table public.child_pin_credentials enable row level security;
alter table public.family_audit_events enable row level security;
revoke all on public.families, public.family_members, public.children,
  public.child_pin_credentials, public.family_audit_events from public, anon, authenticated, service_role;
-- Reads occur only after Edge authorization. Writes use the transactional functions below.
grant select on public.families, public.family_members, public.children to service_role;

create function public.create_family_for_adult(p_actor_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family public.families;
  v_created boolean := false;
begin
  if p_request_id is null or not exists (
    select 1 from auth.users where id = p_actor_id and email_confirmed_at is not null
  ) or not exists (
    select 1 from public.adult_pin_credentials where adult_user_id = p_actor_id
  ) then
    raise exception using message = 'ADULT_SETUP_REQUIRED', errcode = 'P0001';
  end if;
  insert into public.families(created_by, creation_request_id)
    values (p_actor_id, p_request_id)
    on conflict (created_by, creation_request_id) do nothing
    returning * into v_family;
  v_created := found;
  if not v_created then
    select * into v_family from public.families
      where created_by = p_actor_id and creation_request_id = p_request_id for update;
    if v_family.status <> 'active' or not exists (
      select 1 from public.family_members where family_id = v_family.id
        and adult_user_id = p_actor_id and status = 'active'
    ) then
      raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
    end if;
  else
    insert into public.family_members(family_id, adult_user_id) values (v_family.id, p_actor_id);
    insert into public.family_audit_events(family_id, actor_id, event_type)
      values (v_family.id, p_actor_id, 'family.created');
  end if;
  return jsonb_build_object('id',v_family.id,'status',v_family.status,'createdAt',v_family.created_at);
end;
$$;

create function public.create_child_with_pin(
  p_actor_id uuid, p_family_id uuid, p_child_id uuid, p_display_name text,
  p_school_year integer, p_avatar_id text, p_pin_hash text, p_salt text,
  p_fingerprint text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_child public.children;
  v_fingerprint text;
begin
  if not exists (select 1 from auth.users where id = p_actor_id and email_confirmed_at is not null)
    or not exists (select 1 from public.adult_pin_credentials where adult_user_id = p_actor_id) then
    raise exception using message = 'ADULT_SETUP_REQUIRED', errcode = 'P0001';
  end if;
  -- Serialize child creation within the family and preserve authorization during the write.
  perform 1 from public.families where id = p_family_id and status = 'active' for update;
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  perform 1 from public.family_members where family_id = p_family_id
    and adult_user_id = p_actor_id and status = 'active' for share;
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  select * into v_child from public.children where id = p_child_id;
  if found then
    select creation_fingerprint into v_fingerprint
      from public.child_pin_credentials where child_id = p_child_id;
    if v_child.family_id <> p_family_id or v_fingerprint is distinct from p_fingerprint then
      raise exception using message = 'REQUEST_CONFLICT', errcode = 'P0001';
    end if;
  else
    insert into public.children(id,family_id,display_name,school_year,avatar_id)
      values(p_child_id,p_family_id,btrim(p_display_name),p_school_year,p_avatar_id)
      returning * into v_child;
    insert into public.child_pin_credentials(child_id,pin_hash,salt,iterations,creation_fingerprint)
      values(v_child.id,p_pin_hash,p_salt,600000,p_fingerprint);
    insert into public.family_audit_events(family_id,actor_id,event_type,payload)
      values(p_family_id,p_actor_id,'child.created',jsonb_build_object('childId',v_child.id));
  end if;
  return jsonb_build_object('id',v_child.id,'familyId',v_child.family_id,
    'displayName',v_child.display_name,'schoolYear',v_child.school_year,
    'avatarId',v_child.avatar_id,'createdAt',v_child.created_at);
end;
$$;

revoke all on function public.create_family_for_adult(uuid,uuid) from public,anon,authenticated;
revoke all on function public.create_child_with_pin(uuid,uuid,uuid,text,integer,text,text,text,text) from public,anon,authenticated;
grant execute on function public.create_family_for_adult(uuid,uuid) to service_role;
grant execute on function public.create_child_with_pin(uuid,uuid,uuid,text,integer,text,text,text,text) to service_role;

notify pgrst, 'reload schema';
commit;
