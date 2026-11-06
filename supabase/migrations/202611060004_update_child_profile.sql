begin;

-- Edição do perfil infantil pelo adulto (alcunha, avatar, ano escolar e, opcionalmente, PIN).
-- Autorização do responsável (PIN desbloqueado) é validada na Edge Function antes desta chamada.
-- Ao alterar o PIN: substitui hash/salt, avança updated_at (as sessões infantis ficam
-- inválidas porque estão ligadas a credential_updated_at), revoga sessões ativas e limpa
-- o bloqueio de tentativas. Nenhum PIN ou hash é registado na auditoria.
create function public.update_child_profile(
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
    or p_school_year is null or p_school_year not between 1 and 4
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

revoke all on function public.update_child_profile(uuid,uuid,uuid,text,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.update_child_profile(uuid,uuid,uuid,text,integer,text,text,text) to service_role;

notify pgrst, 'reload schema';
commit;
