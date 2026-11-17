-- Vários responsáveis por família: convites por email, aceitar, cancelar e remover.
-- Regras:
--   * todos os responsáveis ativos têm as mesmas permissões (convidar, remover, etc.);
--   * no máximo 4 responsáveis por família (ativos + convites pendentes válidos);
--   * no máximo 10 convites criados por família em 24 h (anti-spam de emails);
--   * o convite vale 7 dias, é de uso único e só o aceita quem tiver o email convidado;
--   * um adulto pertence a uma só família: se já estiver numa família com crianças,
--     não pode aceitar; uma família vazia é fechada (ou abandonada, se tiver outros adultos);
--   * a família nunca fica sem responsáveis (não se remove o último).
-- O token do convite só existe no link do email; aqui guarda-se apenas o SHA-256 (hex).
begin;

create table public.family_invitations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  email text not null check (
    email = lower(btrim(email)) and char_length(email) between 3 and 254
    and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  invited_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz
);
-- Um só convite pendente por email em cada família (reenviar substitui o anterior).
create unique index family_invitations_pending_email_idx
  on public.family_invitations(family_id, email) where status = 'pending';
create index family_invitations_family_created_idx
  on public.family_invitations(family_id, created_at);

alter table public.family_invitations enable row level security;
revoke all on public.family_invitations from public, anon, authenticated, service_role;

-- Garante que o adulto é responsável ativo de uma família ativa (bloqueia a família).
create function public.family_require_member(p_actor_id uuid, p_family_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.families where id = p_family_id and status = 'active' for update;
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  perform 1 from public.family_members where family_id = p_family_id
    and adult_user_id = p_actor_id and status = 'active';
  if not found then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
end;
$$;

-- Criar (ou reenviar) um convite. Devolve o convite; a Edge Function envia o email.
create function public.family_invite_adult(
  p_actor_id uuid, p_family_id uuid, p_email text, p_token_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_inv public.family_invitations;
begin
  perform public.family_require_member(p_actor_id, p_family_id);
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or char_length(v_email) > 254
     or coalesce(p_token_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception using message = 'INVALID_REQUEST', errcode = 'P0001';
  end if;
  if exists (select 1 from public.family_members m join auth.users u on u.id = m.adult_user_id
             where m.family_id = p_family_id and m.status = 'active' and lower(u.email) = v_email) then
    raise exception using message = 'ALREADY_MEMBER', errcode = 'P0001';
  end if;
  if (select count(*) from public.family_invitations
      where family_id = p_family_id and created_at > now() - interval '24 hours') >= 10 then
    raise exception using message = 'RATE_LIMITED', errcode = 'P0001';
  end if;
  -- Reenviar: o convite pendente anterior para o mesmo email deixa de valer.
  update public.family_invitations set status = 'cancelled', cancelled_at = now()
    where family_id = p_family_id and email = v_email and status = 'pending';
  if (select count(*) from public.family_members where family_id = p_family_id and status = 'active')
     + (select count(*) from public.family_invitations
        where family_id = p_family_id and status = 'pending' and expires_at > now()) >= 4 then
    raise exception using message = 'MEMBER_LIMIT', errcode = 'P0001';
  end if;
  insert into public.family_invitations(family_id, email, token_hash, invited_by, expires_at)
    values (p_family_id, v_email, p_token_hash, p_actor_id, now() + interval '7 days')
    returning * into v_inv;
  insert into public.family_audit_events(family_id, actor_id, event_type, payload)
    values (p_family_id, p_actor_id, 'invitation.created', jsonb_build_object('invitationId', v_inv.id));
  return jsonb_build_object('id', v_inv.id, 'email', v_inv.email, 'status', 'pending',
    'createdAt', v_inv.created_at, 'expiresAt', v_inv.expires_at);
end;
$$;

-- Dados do convite para o ecrã «Aceitar convite» (sem exigir sessão do convidado).
create function public.family_invitation_preview(p_token_hash text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_inv public.family_invitations;
  v_inviter text;
begin
  select * into v_inv from public.family_invitations where token_hash = p_token_hash;
  if not found or v_inv.status = 'cancelled'
     or not exists (select 1 from public.families where id = v_inv.family_id and status = 'active') then
    return jsonb_build_object('status', 'invalid');
  end if;
  select email into v_inviter from auth.users where id = v_inv.invited_by;
  return jsonb_build_object(
    'status', case when v_inv.status = 'accepted' then 'accepted'
                   when v_inv.expires_at <= now() then 'expired' else 'pending' end,
    'email', v_inv.email, 'invitedBy', v_inviter, 'expiresAt', v_inv.expires_at);
end;
$$;

-- Aceitar o convite. Idempotente para o mesmo adulto.
create function public.family_accept_invitation(p_actor_id uuid, p_token_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_inv public.family_invitations;
  v_email text;
  v_other uuid;
begin
  select lower(email) into v_email from auth.users
    where id = p_actor_id and email_confirmed_at is not null;
  if v_email is null or not exists (
    select 1 from public.adult_pin_credentials where adult_user_id = p_actor_id) then
    raise exception using message = 'ADULT_SETUP_REQUIRED', errcode = 'P0001';
  end if;
  select * into v_inv from public.family_invitations where token_hash = p_token_hash for update;
  if not found or v_inv.status = 'cancelled' then
    raise exception using message = 'INVITATION_INVALID', errcode = 'P0001';
  end if;
  if v_inv.status = 'accepted' then
    if v_inv.accepted_by = p_actor_id then
      return jsonb_build_object('familyId', v_inv.family_id);
    end if;
    raise exception using message = 'INVITATION_INVALID', errcode = 'P0001';
  end if;
  if v_inv.expires_at <= now() then
    raise exception using message = 'INVITATION_EXPIRED', errcode = 'P0001';
  end if;
  if v_inv.email <> v_email then
    raise exception using message = 'INVITATION_EMAIL_MISMATCH', errcode = 'P0001';
  end if;

  -- Bloqueia por ordem estável a família do convite e as outras famílias do adulto.
  perform 1 from public.families f
    where f.id = v_inv.family_id
       or (f.status = 'active' and exists (select 1 from public.family_members m
             where m.family_id = f.id and m.adult_user_id = p_actor_id and m.status = 'active'))
    order by f.id for update;
  if not exists (select 1 from public.families where id = v_inv.family_id and status = 'active') then
    raise exception using message = 'INVITATION_INVALID', errcode = 'P0001';
  end if;
  if exists (select 1 from public.family_members where family_id = v_inv.family_id
             and adult_user_id = p_actor_id and status = 'active') then
    raise exception using message = 'ALREADY_MEMBER', errcode = 'P0001';
  end if;

  -- Uma família por adulto: só sai de famílias sem crianças.
  if exists (select 1 from public.family_members m
             join public.families f on f.id = m.family_id and f.status = 'active'
             where m.adult_user_id = p_actor_id and m.status = 'active'
               and exists (select 1 from public.children c where c.family_id = f.id)) then
    raise exception using message = 'ALREADY_IN_FAMILY', errcode = 'P0001';
  end if;
  for v_other in
    select m.family_id from public.family_members m
    join public.families f on f.id = m.family_id and f.status = 'active'
    where m.adult_user_id = p_actor_id and m.status = 'active'
    order by m.family_id
  loop
    update public.family_members set status = 'left'
      where family_id = v_other and adult_user_id = p_actor_id;
    insert into public.family_audit_events(family_id, actor_id, event_type)
      values (v_other, p_actor_id, 'member.left');
    if not exists (select 1 from public.family_members where family_id = v_other and status = 'active') then
      update public.families set status = 'closed', closed_at = now() where id = v_other;
      insert into public.family_audit_events(family_id, actor_id, event_type)
        values (v_other, p_actor_id, 'family.closed');
    end if;
  end loop;

  if (select count(*) from public.family_members
      where family_id = v_inv.family_id and status = 'active') >= 4 then
    raise exception using message = 'MEMBER_LIMIT', errcode = 'P0001';
  end if;
  insert into public.family_members(family_id, adult_user_id) values (v_inv.family_id, p_actor_id)
    on conflict (family_id, adult_user_id) do update set status = 'active', joined_at = now();
  update public.family_invitations
    set status = 'accepted', accepted_at = now(), accepted_by = p_actor_id where id = v_inv.id;
  insert into public.family_audit_events(family_id, actor_id, event_type, payload)
    values (v_inv.family_id, p_actor_id, 'member.joined', jsonb_build_object('invitationId', v_inv.id));
  return jsonb_build_object('familyId', v_inv.family_id);
end;
$$;

-- Cancelar um convite pendente.
create function public.family_cancel_invitation(
  p_actor_id uuid, p_family_id uuid, p_invitation_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform public.family_require_member(p_actor_id, p_family_id);
  update public.family_invitations set status = 'cancelled', cancelled_at = now()
    where id = p_invitation_id and family_id = p_family_id and status = 'pending';
  if not found then
    raise exception using message = 'INVITATION_INVALID', errcode = 'P0001';
  end if;
  insert into public.family_audit_events(family_id, actor_id, event_type, payload)
    values (p_family_id, p_actor_id, 'invitation.cancelled', jsonb_build_object('invitationId', p_invitation_id));
  return jsonb_build_object('id', p_invitation_id, 'status', 'cancelled');
end;
$$;

-- Remover um responsável (ou sair, se for o próprio). Nunca o último.
create function public.family_remove_member(
  p_actor_id uuid, p_family_id uuid, p_adult_user_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_self boolean := p_actor_id = p_adult_user_id;
begin
  perform public.family_require_member(p_actor_id, p_family_id);
  if not exists (select 1 from public.family_members where family_id = p_family_id
                 and adult_user_id = p_adult_user_id and status = 'active') then
    raise exception using message = 'MEMBER_NOT_FOUND', errcode = 'P0001';
  end if;
  if (select count(*) from public.family_members
      where family_id = p_family_id and status = 'active') <= 1 then
    raise exception using message = 'LAST_MEMBER', errcode = 'P0001';
  end if;
  update public.family_members set status = case when v_self then 'left' else 'removed' end
    where family_id = p_family_id and adult_user_id = p_adult_user_id;
  insert into public.family_audit_events(family_id, actor_id, event_type, payload)
    values (p_family_id, p_actor_id, case when v_self then 'member.left' else 'member.removed' end,
            jsonb_build_object('adultUserId', p_adult_user_id));
  return jsonb_build_object('adultUserId', p_adult_user_id,
    'status', case when v_self then 'left' else 'removed' end);
end;
$$;

-- Responsáveis ativos e convites pendentes (para o ecrã «Responsáveis»).
create function public.family_list_members(p_actor_id uuid, p_family_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.family_members m join public.families f on f.id = m.family_id
                 where m.family_id = p_family_id and m.adult_user_id = p_actor_id
                   and m.status = 'active' and f.status = 'active') then
    raise exception using message = 'FAMILY_NOT_FOUND', errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('adultUserId', m.adult_user_id, 'email', u.email,
               'joinedAt', m.joined_at, 'isMe', m.adult_user_id = p_actor_id) order by m.joined_at)
      from public.family_members m join auth.users u on u.id = m.adult_user_id
      where m.family_id = p_family_id and m.status = 'active'), '[]'::jsonb),
    'invitations', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email,
               'createdAt', i.created_at, 'expiresAt', i.expires_at,
               'expired', i.expires_at <= now()) order by i.created_at)
      from public.family_invitations i
      where i.family_id = p_family_id and i.status = 'pending'), '[]'::jsonb));
end;
$$;

revoke all on function public.family_require_member(uuid,uuid) from public, anon, authenticated;
revoke all on function public.family_invite_adult(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.family_invitation_preview(text) from public, anon, authenticated;
revoke all on function public.family_accept_invitation(uuid,text) from public, anon, authenticated;
revoke all on function public.family_cancel_invitation(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.family_remove_member(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.family_list_members(uuid,uuid) from public, anon, authenticated;
grant execute on function public.family_invite_adult(uuid,uuid,text,text) to service_role;
grant execute on function public.family_invitation_preview(text) to service_role;
grant execute on function public.family_accept_invitation(uuid,text) to service_role;
grant execute on function public.family_cancel_invitation(uuid,uuid,uuid) to service_role;
grant execute on function public.family_remove_member(uuid,uuid,uuid) to service_role;
grant execute on function public.family_list_members(uuid,uuid) to service_role;

notify pgrst, 'reload schema';
commit;
