begin;

-- Redefinição do PIN parental após reautenticação recente (verificada na Edge Function).
-- Numa única transação: substitui o hash, avança updated_at (invalida todas as
-- autorizações parent_unlock_sessions ligadas à versão anterior), limpa o bloqueio
-- de tentativas e revoga explicitamente as autorizações ativas.
create function public.reset_parent_pin(
  p_actor_id uuid,
  p_pin_hash text,
  p_salt text,
  p_iterations integer,
  p_algorithm text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_updated_at timestamptz;
begin
  if not exists(select 1 from auth.users where id=p_actor_id and email_confirmed_at is not null) then
    return jsonb_build_object('error','AUTH_REQUIRED');
  end if;
  if p_pin_hash !~ '^[0-9a-f]{64}$' or p_salt !~ '^[0-9a-f]{32}$'
    or p_iterations <> 600000 or p_algorithm <> 'pbkdf2-sha256-hmac-pepper-v1' then
    return jsonb_build_object('error','STORAGE_UNAVAILABLE');
  end if;

  -- clock_timestamp garante uma versão diferente mesmo dentro da mesma transação.
  update public.adult_pin_credentials
    set pin_hash=p_pin_hash, salt=p_salt, iterations=p_iterations,
        algorithm=p_algorithm, updated_at=clock_timestamp()
    where adult_user_id=p_actor_id
    returning updated_at into v_updated_at;
  if not found then return jsonb_build_object('error','PIN_NOT_CONFIGURED'); end if;

  update public.adult_pin_attempts
    set attempt_count=0, blocked_until=null, window_started_at=now(),
        challenge_id=null, challenge_expires_at=null
    where adult_user_id=p_actor_id;

  update public.parent_unlock_sessions
    set revoked_at=now()
    where adult_user_id=p_actor_id and revoked_at is null;

  return jsonb_build_object('configured',true);
end;
$$;

revoke all on function public.reset_parent_pin(uuid,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.reset_parent_pin(uuid,text,text,integer,text) to service_role;

comment on table public.adult_pin_credentials is
  'Adult PIN credentials aligned with the ERD. Client access denied; reset only via reset_parent_pin after recent password reauthentication.';

notify pgrst, 'reload schema';
commit;
