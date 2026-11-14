-- Fase 6 — Assinaturas App Store (iOS).
--
-- Mesmo modelo do Google Play: produtos-vaga premium_crianca_1..5 (cada um no seu grupo de
-- assinaturas, para a mesma conta Apple poder ter várias crianças Premium).
--
-- Fluxo:
--   1. O responsável pede uma oferta (billing_apple_offer): o servidor escolhe a primeira vaga livre
--      da família e regista a intenção (família, criança, produto).
--   2. A app compra esse produto com appAccountToken = id da família (UUID).
--   3. A compra é verificada no servidor (App Store Server API) — pela app logo a seguir à compra e
--      pelas App Store Server Notifications V2. billing_apply_app_store_subscription liga o
--      originalTransactionId à criança da intenção e aplica o estado atual (idempotente).
--
-- Diferenças da Apple:
--   • O originalTransactionId mantém-se quando a assinatura volta a ser comprada depois de expirar
--     (mesmo grupo): se houver uma intenção nova para o produto, a vaga passa para essa criança.
--   • Não há confirmação (acknowledge) nem cancelamento/reembolso pelo servidor: compras recusadas
--     ficam registadas no histórico e o reembolso é pedido pelo responsável à Apple.
begin;

create table public.app_store_purchase_intents (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid references public.children(id) on delete set null,
  product_id text not null check (product_id ~ '^premium_crianca_[1-9][0-9]*$'),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  original_transaction_id text,
  consumed_at timestamptz
);
create index app_store_purchase_intents_family_product_idx
  on public.app_store_purchase_intents(family_id, product_id, created_at desc);

alter table public.app_store_purchase_intents enable row level security;
revoke all on public.app_store_purchase_intents from public, anon, authenticated, service_role;
grant select on public.app_store_purchase_intents to service_role;

-- Oferta App Store para uma criança: valida o responsável e escolhe a vaga (produto) livre.
create function public.billing_apple_offer(p_actor_id uuid, p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ctx jsonb;
  v_family uuid;
  v_product text;
begin
  v_ctx := public.billing_checkout_context(p_actor_id, p_child_id);  -- mesmas regras do Stripe e da Google Play
  if v_ctx ? 'error' then return v_ctx; end if;
  v_family := (v_ctx->>'familyId')::uuid;
  select 'premium_crianca_' || n into v_product
    from generate_series(1, public.billing_setting('max_premium_children')) n
   where not exists (
     select 1 from public.child_subscriptions s
      where s.family_id = v_family and s.channel = 'app_store'
        and s.store_product_id = 'premium_crianca_' || n
        and s.status in ('pending','active','in_grace'))
   order by n limit 1;
  if v_product is null then return jsonb_build_object('error', 'MAX_PREMIUM_CHILDREN_REACHED'); end if;
  insert into public.app_store_purchase_intents(family_id, child_id, product_id, created_by)
    values (v_family, p_child_id, v_product, p_actor_id);
  return jsonb_build_object('familyId', v_family, 'childId', p_child_id, 'productId', v_product);
end;
$$;

-- Aplica o estado ATUAL de uma assinatura App Store (App Store Server API, Get All Subscription Statuses).
-- p: {eventId, eventType, originalTransactionId, transactionId, productId, familyId (appAccountToken),
--     status (1 ativa, 2 expirada, 3 nova tentativa de cobrança, 4 tolerância, 5 revogada),
--     purchaseDate, expiresDate, gracePeriodExpiresDate, autoRenew, priceMilli, currency, environment}
-- Devolve {ok, plan, childId} | {ignored} | {error: UNKNOWN_FAMILY | NO_PURCHASE_INTENT |
--   CHILD_ALREADY_PREMIUM | MAX_PREMIUM_CHILDREN_REACHED}.
create function public.billing_apply_app_store_subscription(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_original text := p->>'originalTransactionId';
  v_family uuid := nullif(p->>'familyId', '')::uuid;
  v_child uuid;
  v_status text;
  v_start timestamptz := nullif(p->>'purchaseDate', '')::timestamptz;
  v_end timestamptz := nullif(p->>'expiresDate', '')::timestamptz;
  v_grace_end timestamptz := nullif(p->>'gracePeriodExpiresDate', '')::timestamptz;
  v_renew boolean := coalesce((p->>'autoRenew')::boolean, false);
  v_price integer := case when nullif(p->>'priceMilli', '') is null then null
                          else round((p->>'priceMilli')::numeric / 10)::integer end;
  v_grace timestamptz;
  v_row public.child_subscriptions;
  v_intent public.app_store_purchase_intents;
  v_result jsonb;
begin
  if v_original is null then return jsonb_build_object('error', 'INVALID_TRANSACTION'); end if;
  select * into v_row from public.child_subscriptions
   where channel = 'app_store' and external_id = v_original for update;
  if v_row.id is not null then
    v_family := v_row.family_id; v_child := v_row.child_id;
  end if;

  v_status := case (p->>'status')::integer
    when 1 then 'active'
    when 4 then 'in_grace'     -- período de tolerância de cobrança (acesso mantém-se)
    when 5 then 'revoked'      -- reembolso ou revogação pela Apple
    else 'expired' end;        -- 2 expirada, 3 nova tentativa de cobrança sem tolerância
  if v_status = 'active' and v_end is not null and v_end <= now() then v_status := 'expired'; end if;
  v_grace := case
    when v_status = 'active' and v_renew then v_end + make_interval(hours => public.billing_setting('store_renewal_leeway_hours'))
    when v_status = 'in_grace' then greatest(coalesce(v_grace_end, v_end), v_end, now())
    else null end;
  if v_status in ('expired', 'revoked') then v_end := least(coalesce(v_end, now()), now()); v_renew := false; end if;

  begin
    if v_row.id is not null then
      -- Voltou a ser comprada depois de terminar (mesmo originalTransactionId): a vaga passa para a
      -- criança da intenção mais recente, se houver uma intenção nova para este produto.
      if v_row.status not in ('pending','active','in_grace') and v_status in ('active','in_grace') then
        select * into v_intent from public.app_store_purchase_intents
         where family_id = v_family and product_id = v_row.store_product_id and consumed_at is null
           and created_at >= coalesce(v_row.current_period_end, v_row.updated_at)  -- pedida depois de terminar
         order by created_at desc limit 1 for update;
        if v_intent.id is not null then
          update public.app_store_purchase_intents set consumed_at = now(), original_transaction_id = v_original
           where id = v_intent.id;
          if v_intent.child_id is not null and exists (select 1 from public.children
               where id = v_intent.child_id and family_id = v_family) then
            v_child := v_intent.child_id;
          end if;
        end if;
        if v_child is not null and exists (select 1 from public.child_subscriptions
             where child_id = v_child and id <> v_row.id and status in ('pending','active','in_grace')) then
          raise exception using message = 'CHILD_ALREADY_PREMIUM', errcode = 'P0001';
        end if;
        -- Premium manual da mesma criança é substituído pela assinatura paga.
        with superseded as (
          update public.child_subscriptions set status = 'revoked'
           where child_id = v_child and channel = 'manual' and status in ('pending','active','in_grace')
          returning id
        )
        insert into public.billing_events(family_id, child_id, subscription_id, source, event_type)
        select v_family, v_child, id, 'system', 'subscription.superseded' from superseded;
      end if;
      update public.child_subscriptions
         set child_id = v_child, status = v_status, auto_renew = v_renew,
             current_period_start = coalesce(v_start, current_period_start),
             current_period_end = coalesce(v_end, current_period_end), grace_until = v_grace,
             price_amount_cents = coalesce(v_price, price_amount_cents),
             currency = coalesce(upper(p->>'currency'), currency)
       where id = v_row.id returning * into v_row;
      v_result := jsonb_build_object('ok', true);
    elsif v_family is null or not exists (select 1 from public.families where id = v_family) then
      v_result := jsonb_build_object('error', 'UNKNOWN_FAMILY');
    elsif v_status not in ('active', 'in_grace') then
      v_result := jsonb_build_object('ignored', true);
    else
      select * into v_intent from public.app_store_purchase_intents
       where family_id = v_family and product_id = p->>'productId' and consumed_at is null
       order by created_at desc limit 1 for update;
      if v_intent.id is null then raise exception using message = 'NO_PURCHASE_INTENT', errcode = 'P0001'; end if;
      update public.app_store_purchase_intents set consumed_at = now(), original_transaction_id = v_original
       where id = v_intent.id;
      v_child := v_intent.child_id;
      if v_child is not null and not exists (select 1 from public.children where id = v_child and family_id = v_family) then
        v_child := null;
      end if;
      if v_child is not null then
        with superseded as (
          update public.child_subscriptions set status = 'revoked'
           where child_id = v_child and channel = 'manual' and status in ('pending','active','in_grace')
          returning id
        )
        insert into public.billing_events(family_id, child_id, subscription_id, source, event_type)
        select v_family, v_child, id, 'system', 'subscription.superseded' from superseded;
        if exists (select 1 from public.child_subscriptions
                    where child_id = v_child and status in ('pending','active','in_grace')) then
          raise exception using message = 'CHILD_ALREADY_PREMIUM', errcode = 'P0001';
        end if;
      end if;
      insert into public.child_subscriptions(family_id, child_id, channel, external_id, store_product_id,
          status, auto_renew, current_period_start, current_period_end, grace_until, price_amount_cents, currency)
        values (v_family, v_child, 'app_store', v_original, p->>'productId', v_status, v_renew, v_start, v_end, v_grace,
          v_price, upper(p->>'currency'))
        returning * into v_row;
      v_result := jsonb_build_object('ok', true);
    end if;
  exception
    when unique_violation then v_result := jsonb_build_object('error', 'CHILD_ALREADY_PREMIUM');
    when raise_exception then
      if sqlerrm in ('CHILD_ALREADY_PREMIUM', 'MAX_PREMIUM_CHILDREN_REACHED', 'NO_PURCHASE_INTENT') then
        v_result := jsonb_build_object('error', sqlerrm);
      else raise; end if;
  end;

  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type, external_event_id, payload)
    values ((select id from public.families where id = v_family), v_child, v_row.id, 'app_store',
            coalesce(p->>'eventType', 'subscription.sync'), nullif(p->>'eventId', ''),
            (p - 'eventId' - 'eventType') || jsonb_build_object('result', v_result, 'subscriptionId', v_row.id))
    on conflict (source, external_event_id) where external_event_id is not null do nothing;

  if v_result ? 'ok' then
    v_result := v_result || jsonb_build_object('childId', v_child,
      'plan', case when v_child is null then null else public.child_access(v_child)->>'plan' end);
  end if;
  return v_result;
end;
$$;

create function public.billing_apple_event_seen(p_event_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.billing_events where source = 'app_store' and external_event_id = p_event_id)
$$;

revoke all on function public.billing_apple_offer(uuid,uuid), public.billing_apply_app_store_subscription(jsonb),
  public.billing_apple_event_seen(text) from public, anon, authenticated;
grant execute on function public.billing_apple_offer(uuid,uuid), public.billing_apply_app_store_subscription(jsonb),
  public.billing_apple_event_seen(text) to service_role;

notify pgrst, 'reload schema';
commit;
