begin;

-- Ações de administração sobre faturação (ferramenta local tools/admin), apenas service_role:
--   • alterar limites comerciais (billing_settings), com margens seguras e registo no histórico;
--   • contexto e registo para cancelar assinaturas pagas (o cancelamento em si é feito pela Edge Function
--     admin-billing na plataforma de origem — Stripe ou Google Play — e chega de volta pelos webhooks).

-- ---------------------------------------------------------------------------
-- Limites comerciais
-- ---------------------------------------------------------------------------
create function public.admin_billing_setting_bounds(p_key text)
returns int4range language sql immutable set search_path = '' as $$
  select case p_key
    when 'free_child_slots' then int4range(0, 5, '[]')
    when 'max_premium_children' then int4range(1, 5, '[]')       -- 5 = produtos-vaga criados nas lojas
    when 'free_max_questions' then int4range(1, 100, '[]')
    when 'free_daily_assignments' then int4range(1, 50, '[]')
    when 'free_daily_attempts' then int4range(1, 50, '[]')
    when 'paid_grace_days' then int4range(0, 30, '[]')
    when 'stripe_renewal_leeway_hours' then int4range(0, 168, '[]')
    when 'store_renewal_leeway_hours' then int4range(0, 168, '[]')
  end
$$;

create function public.admin_set_billing_setting(p_key text, p_value integer, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_old integer;
  v_bounds int4range := public.admin_billing_setting_bounds(p_key);
  v_family uuid;
begin
  select value into v_old from public.billing_settings where key = p_key for update;
  if not found or v_bounds is null then raise exception using message = 'SETTING_NOT_FOUND', errcode = 'P0001'; end if;
  if p_value is null or not v_bounds @> p_value then
    raise exception using message = 'SETTING_OUT_OF_RANGE', errcode = 'P0001',
      detail = format('Valores permitidos: %s a %s.', lower(v_bounds), upper(v_bounds) - 1);
  end if;
  if p_value = v_old then return jsonb_build_object('key', p_key, 'value', v_old, 'changed', false); end if;

  update public.billing_settings set value = p_value, updated_at = now() where key = p_key;
  insert into public.billing_events(source, event_type, payload)
    values ('admin', 'setting.updated', jsonb_build_object('key', p_key, 'from', v_old, 'to', p_value, 'note', p_note));

  -- Mais vagas gratuitas: atribuí-las já às crianças sem Premium. Menos vagas: quem já tem vaga mantém-na.
  if p_key = 'free_child_slots' and p_value > v_old then
    for v_family in select id from public.families where status = 'active' loop
      perform public.billing_rebalance_family(v_family);
    end loop;
  end if;
  return jsonb_build_object('key', p_key, 'value', p_value, 'changed', true);
end;
$$;

-- Margens permitidas, para o admin mostrar no formulário.
create or replace function public.admin_list_billing_settings()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'description', s.description,
      'updatedAt', s.updated_at,
      'min', lower(public.admin_billing_setting_bounds(s.key)),
      'max', upper(public.admin_billing_setting_bounds(s.key)) - 1) order by s.key), '[]'::jsonb)
  from public.billing_settings s;
$$;

-- ---------------------------------------------------------------------------
-- Cancelamento de assinaturas (usado pela Edge Function admin-billing)
-- ---------------------------------------------------------------------------
create function public.admin_subscription_context(p_subscription_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_build_object(
      'id', s.id, 'channel', s.channel, 'externalId', s.external_id, 'productId', s.store_product_id,
      'status', s.status, 'autoRenew', s.auto_renew, 'currentPeriodEnd', s.current_period_end,
      'familyId', s.family_id, 'childId', s.child_id)
    from public.child_subscriptions s where s.id = p_subscription_id),
    jsonb_build_object('error', 'SUBSCRIPTION_NOT_FOUND'));
$$;

create function public.admin_log_subscription_action(p_subscription_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type, payload)
  select s.family_id, s.child_id, s.id, 'admin', p_action, coalesce(p_payload, '{}'::jsonb)
    from public.child_subscriptions s where s.id = p_subscription_id;
$$;

revoke all on function public.admin_billing_setting_bounds(text), public.admin_set_billing_setting(text, integer, text),
  public.admin_subscription_context(uuid), public.admin_log_subscription_action(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.admin_billing_setting_bounds(text), public.admin_set_billing_setting(text, integer, text),
  public.admin_subscription_context(uuid), public.admin_log_subscription_action(uuid, text, jsonb)
  to service_role;

notify pgrst, 'reload schema';
commit;
