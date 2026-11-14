begin;

-- Eliminação de conta: antes de apagar as famílias, a Edge Function `account` cancela as
-- assinaturas pagas dessas famílias na plataforma de origem (senão o responsável continuaria a pagar).
--   • Stripe: cancelada de imediato (sem novas cobranças).
--   • Google Play: renovação cancelada (sem novas cobranças).
--   • App Store: a Apple não permite cancelar pelo servidor — a app avisa o responsável.
-- Só conta as famílias que serão apagadas (onde o adulto é o único membro ativo), as mesmas
-- regras de delete_account_data.
create function public.account_deletion_subscriptions(p_actor_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'channel', s.channel, 'externalId', s.external_id, 'productId', s.store_product_id,
      'autoRenew', s.auto_renew) order by s.created_at), '[]'::jsonb)
  from public.child_subscriptions s
  join public.families f on f.id = s.family_id
  where s.channel in ('stripe', 'google_play', 'app_store')
    and s.status in ('pending', 'active', 'in_grace')
    and (f.created_by = p_actor_id
         or exists (select 1 from public.family_members m where m.family_id = f.id and m.adult_user_id = p_actor_id))
    and not exists (select 1 from public.family_members m
                     where m.family_id = f.id and m.status = 'active' and m.adult_user_id <> p_actor_id);
$$;

revoke all on function public.account_deletion_subscriptions(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_subscriptions(uuid) to service_role;

notify pgrst, 'reload schema';
commit;
