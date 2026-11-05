begin;
create table public.adult_pin_attempts (
  adult_user_id uuid primary key references auth.users(id) on delete cascade,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz,
  challenge_id uuid,
  challenge_expires_at timestamptz
);
create table public.parent_unlock_sessions (
  id uuid primary key default gen_random_uuid(),
  adult_user_id uuid not null references auth.users(id) on delete cascade,
  auth_session_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  credential_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '5 minutes',
  revoked_at timestamptz
);
create index parent_unlock_sessions_adult_expiry_idx on public.parent_unlock_sessions(adult_user_id,expires_at);
alter table public.adult_pin_attempts enable row level security;
alter table public.parent_unlock_sessions enable row level security;
revoke all on public.adult_pin_attempts,public.parent_unlock_sessions from public,anon,authenticated,service_role;

create function public.begin_parent_pin_verify(p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_pin public.adult_pin_credentials;
  v_attempt public.adult_pin_attempts;
  v_challenge uuid;
begin
  if not exists(select 1 from auth.users where id=p_actor_id and email_confirmed_at is not null) then
    return jsonb_build_object('error','AUTH_REQUIRED');
  end if;
  select * into v_pin from public.adult_pin_credentials where adult_user_id=p_actor_id;
  if not found then return jsonb_build_object('error','PIN_NOT_CONFIGURED'); end if;
  insert into public.adult_pin_attempts(adult_user_id) values(p_actor_id) on conflict do nothing;
  select * into v_attempt from public.adult_pin_attempts where adult_user_id=p_actor_id for update;
  if v_attempt.blocked_until > now() then
    return jsonb_build_object('error','PIN_LOCKED','retryAfter',ceil(extract(epoch from v_attempt.blocked_until-now())));
  end if;
  if v_attempt.blocked_until is not null or v_attempt.window_started_at < now()-interval '15 minutes' then
    v_attempt.attempt_count:=0; v_attempt.window_started_at:=now();
  end if;
  if v_attempt.challenge_expires_at>now() then return jsonb_build_object('error','PIN_BUSY'); end if;
  v_challenge:=gen_random_uuid();
  update public.adult_pin_attempts set attempt_count=v_attempt.attempt_count+1,
    window_started_at=v_attempt.window_started_at,
    blocked_until=case when v_attempt.attempt_count+1>=5 then now()+interval '5 minutes' else null end,
    challenge_id=v_challenge,challenge_expires_at=now()+interval '30 seconds' where adult_user_id=p_actor_id;
  return jsonb_build_object('challengeId',v_challenge,'hash',v_pin.pin_hash,'salt',v_pin.salt,
    'iterations',v_pin.iterations,'algorithm',v_pin.algorithm,'credentialUpdatedAt',v_pin.updated_at);
end;
$$;

create function public.complete_parent_pin_verify(
  p_actor_id uuid,p_auth_session_id uuid,p_challenge_id uuid,
  p_credential_updated_at timestamptz,p_matches boolean,p_token_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_attempt public.adult_pin_attempts;
  v_unlock public.parent_unlock_sessions;
begin
  select * into v_attempt from public.adult_pin_attempts where adult_user_id=p_actor_id for update;
  if not found or v_attempt.challenge_id is distinct from p_challenge_id
    or v_attempt.challenge_expires_at is null or v_attempt.challenge_expires_at<=now() then
    return jsonb_build_object('error','VERIFY_EXPIRED');
  end if;
  update public.adult_pin_attempts set challenge_id=null,challenge_expires_at=null where adult_user_id=p_actor_id;
  if p_matches is distinct from true then
    return jsonb_build_object('error',case when v_attempt.blocked_until>now() then 'PIN_LOCKED' else 'WRONG_PIN' end,
      'retryAfter',case when v_attempt.blocked_until>now() then ceil(extract(epoch from v_attempt.blocked_until-now())) else 0 end);
  end if;
  if p_auth_session_id is null or not exists(
    select 1 from auth.users u join public.adult_pin_credentials pin on pin.adult_user_id=u.id
      where u.id=p_actor_id and u.email_confirmed_at is not null and pin.updated_at=p_credential_updated_at
  ) then return jsonb_build_object('error','AUTH_REQUIRED'); end if;
  insert into public.parent_unlock_sessions(adult_user_id,auth_session_id,token_hash,credential_updated_at)
    values(p_actor_id,p_auth_session_id,p_token_hash,p_credential_updated_at) returning * into v_unlock;
  update public.adult_pin_attempts set attempt_count=0,blocked_until=null,window_started_at=now() where adult_user_id=p_actor_id;
  return jsonb_build_object('expiresAt',v_unlock.expires_at);
end;
$$;

create function public.use_parent_unlock(
  p_actor_id uuid,p_auth_session_id uuid,p_token_hash text,
  p_touch boolean default false,p_revoke boolean default false
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_unlock public.parent_unlock_sessions;
begin
  select * into v_unlock from public.parent_unlock_sessions
    where adult_user_id=p_actor_id and auth_session_id=p_auth_session_id and token_hash=p_token_hash for update;
  if not found then return jsonb_build_object('error','PARENT_LOCKED'); end if;
  if p_revoke then
    update public.parent_unlock_sessions set revoked_at=coalesce(revoked_at,now()) where id=v_unlock.id;
    return jsonb_build_object('revoked',true);
  end if;
  if v_unlock.revoked_at is not null or v_unlock.expires_at<=now()
    or v_unlock.created_at+interval '12 hours'<=now() or not exists(
      select 1 from auth.users u join public.adult_pin_credentials pin on pin.adult_user_id=u.id
        where u.id=p_actor_id and u.email_confirmed_at is not null and pin.updated_at=v_unlock.credential_updated_at
    ) then return jsonb_build_object('error','PARENT_LOCKED'); end if;
  if p_touch then
    update public.parent_unlock_sessions set last_used_at=now(),
      expires_at=least(now()+interval '5 minutes',created_at+interval '12 hours')
      where id=v_unlock.id returning * into v_unlock;
  end if;
  return jsonb_build_object('expiresAt',v_unlock.expires_at);
end;
$$;
revoke all on function public.begin_parent_pin_verify(uuid) from public,anon,authenticated;
revoke all on function public.complete_parent_pin_verify(uuid,uuid,uuid,timestamptz,boolean,text) from public,anon,authenticated;
revoke all on function public.use_parent_unlock(uuid,uuid,text,boolean,boolean) from public,anon,authenticated;
grant execute on function public.begin_parent_pin_verify(uuid) to service_role;
grant execute on function public.complete_parent_pin_verify(uuid,uuid,uuid,timestamptz,boolean,text) to service_role;
grant execute on function public.use_parent_unlock(uuid,uuid,text,boolean,boolean) to service_role;
notify pgrst,'reload schema';
commit;
