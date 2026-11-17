-- Pré-visualização do convite indica se o e-mail convidado já tem conta, para a app
-- abrir em «Entrar» ou em «Criar conta». Só quem tem o token (o convidado) vê isto.
begin;

create or replace function public.family_invitation_preview(p_token_hash text)
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
    'email', v_inv.email, 'invitedBy', v_inviter, 'expiresAt', v_inv.expires_at,
    'accountExists', exists (select 1 from auth.users where lower(email) = v_inv.email));
end;
$$;

revoke all on function public.family_invitation_preview(text) from public, anon, authenticated;
grant execute on function public.family_invitation_preview(text) to service_role;

notify pgrst, 'reload schema';
commit;
