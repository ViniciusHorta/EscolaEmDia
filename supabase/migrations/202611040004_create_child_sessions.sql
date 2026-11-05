begin;

create table public.child_pin_attempts (
  child_id uuid primary key references public.children(id) on delete cascade,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  challenge_id uuid,
  challenge_expires_at timestamptz
);
create table public.child_sessions (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children(id) on delete cascade,
  device_id uuid, -- Pairing and child_devices will be added in the device-access stage.
  authorized_by uuid not null references auth.users(id),
  access_token_hash text not null unique check (access_token_hash ~ '^[0-9a-f]{64}$'),
  credential_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check (expires_at > created_at)
);
create index child_sessions_child_expiry_idx on public.child_sessions(child_id, expires_at);
alter table public.child_pin_attempts enable row level security;
alter table public.child_sessions enable row level security;
revoke all on public.child_pin_attempts, public.child_sessions from public, anon, authenticated, service_role;

-- Reserve an attempt BEFORE hashing. Concurrent or abandoned requests cannot
-- bypass the limit: reservations count until a successful verification resets it.
create function public.begin_child_pin_login(p_actor_id uuid, p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_credential public.child_pin_credentials;
  v_attempt public.child_pin_attempts;
  v_family_id uuid;
  v_challenge uuid;
begin
  select c.family_id into v_family_id from public.children c
    join public.families f on f.id = c.family_id and f.status = 'active'
    join public.family_members m on m.family_id = f.id and m.adult_user_id = p_actor_id and m.status = 'active'
    join auth.users u on u.id = p_actor_id and u.email_confirmed_at is not null
    where c.id = p_child_id;
  if not found then return jsonb_build_object('error', 'CHILD_NOT_FOUND'); end if;
  select * into v_credential from public.child_pin_credentials where child_id = p_child_id;
  if not found then return jsonb_build_object('error', 'CHILD_NOT_FOUND'); end if;
  insert into public.child_pin_attempts(child_id) values(p_child_id) on conflict do nothing;
  select * into v_attempt from public.child_pin_attempts where child_id = p_child_id for update;
  if v_attempt.blocked_until > now() then
    return jsonb_build_object('error','PIN_LOCKED','retryAfter',ceil(extract(epoch from v_attempt.blocked_until - now())));
  end if;
  if v_attempt.blocked_until is not null or v_attempt.window_started_at < now() - interval '15 minutes' then
    v_attempt.attempt_count := 0;
    v_attempt.window_started_at := now();
  end if;
  if v_attempt.challenge_expires_at > now() then return jsonb_build_object('error','PIN_BUSY'); end if;
  v_challenge := gen_random_uuid();
  update public.child_pin_attempts set attempt_count = v_attempt.attempt_count + 1,
    window_started_at = v_attempt.window_started_at,
    blocked_until = case when v_attempt.attempt_count + 1 >= 5 then now() + interval '5 minutes' else null end,
    challenge_id = v_challenge, challenge_expires_at = now() + interval '30 seconds'
    where child_id = p_child_id;
  -- This payload is accessible only to the Edge Function, never to Flutter.
  return jsonb_build_object('challengeId',v_challenge,'familyId',v_family_id,
    'hash',v_credential.pin_hash,'salt',v_credential.salt,'iterations',v_credential.iterations,
    'algorithm',v_credential.algorithm,'credentialUpdatedAt',v_credential.updated_at);
end;
$$;

create function public.complete_child_pin_login(
  p_actor_id uuid, p_child_id uuid, p_challenge_id uuid,
  p_credential_updated_at timestamptz, p_matches boolean, p_token_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_child public.children;
  v_attempt public.child_pin_attempts;
  v_session public.child_sessions;
begin
  select * into v_attempt from public.child_pin_attempts where child_id = p_child_id for update;
  if not found or v_attempt.challenge_id is distinct from p_challenge_id
    or v_attempt.challenge_expires_at is null or v_attempt.challenge_expires_at <= now() then
    return jsonb_build_object('error','LOGIN_EXPIRED');
  end if;
  update public.child_pin_attempts set challenge_id = null, challenge_expires_at = null where child_id = p_child_id;
  if p_matches is distinct from true then
    return jsonb_build_object('error', case when v_attempt.blocked_until > now() then 'PIN_LOCKED' else 'INVALID_PIN' end,
      'retryAfter',case when v_attempt.blocked_until > now() then ceil(extract(epoch from v_attempt.blocked_until - now())) else 0 end);
  end if;
  select c.* into v_child from public.children c
    join public.families f on f.id = c.family_id and f.status = 'active'
    join public.family_members m on m.family_id = f.id and m.adult_user_id = p_actor_id and m.status = 'active'
    join auth.users u on u.id = p_actor_id and u.email_confirmed_at is not null
    join public.child_pin_credentials pin on pin.child_id = c.id and pin.updated_at = p_credential_updated_at
    where c.id = p_child_id for share of c, f, m, pin;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  insert into public.child_sessions(child_id, authorized_by, access_token_hash, credential_updated_at, expires_at)
    values(p_child_id, p_actor_id, p_token_hash, p_credential_updated_at, now() + interval '1 hour') returning * into v_session;
  update public.child_pin_attempts set attempt_count = 0, blocked_until = null,
    window_started_at = now() where child_id = p_child_id;
  return jsonb_build_object('sessionId',v_session.id,'expiresAt',v_session.expires_at);
end;
$$;

-- No child ID parameter: the token determines the only profile the caller can see.
create function public.use_child_session(p_token_hash text, p_revoke boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.child_sessions;
  v_child public.children;
begin
  select * into v_session from public.child_sessions where access_token_hash = p_token_hash for update;
  if not found then return jsonb_build_object('error','CHILD_SESSION_EXPIRED'); end if;
  if p_revoke then
    update public.child_sessions set revoked_at = coalesce(revoked_at,now()) where id = v_session.id;
    return jsonb_build_object('revoked',true);
  end if;
  if v_session.revoked_at is not null or v_session.expires_at <= now() then
    return jsonb_build_object('error','CHILD_SESSION_EXPIRED');
  end if;
  select c.* into v_child from public.children c
    join public.families f on f.id = c.family_id and f.status = 'active'
    join public.family_members m on m.family_id = f.id and m.adult_user_id = v_session.authorized_by and m.status = 'active'
    join public.child_pin_credentials pin on pin.child_id = c.id and pin.updated_at = v_session.credential_updated_at
    where c.id = v_session.child_id;
  if not found then return jsonb_build_object('error','CHILD_SESSION_EXPIRED'); end if;
  return jsonb_build_object('sessionId',v_session.id,'expiresAt',v_session.expires_at,
    'child',jsonb_build_object('id',v_child.id,'familyId',v_child.family_id,'displayName',v_child.display_name,
      'schoolYear',v_child.school_year,'avatarId',v_child.avatar_id));
end;
$$;

revoke all on function public.begin_child_pin_login(uuid,uuid) from public,anon,authenticated;
revoke all on function public.complete_child_pin_login(uuid,uuid,uuid,timestamptz,boolean,text) from public,anon,authenticated;
revoke all on function public.use_child_session(text,boolean) from public,anon,authenticated;
grant execute on function public.begin_child_pin_login(uuid,uuid) to service_role;
grant execute on function public.complete_child_pin_login(uuid,uuid,uuid,timestamptz,boolean,text) to service_role;
grant execute on function public.use_child_session(text,boolean) to service_role;
notify pgrst, 'reload schema';
commit;
