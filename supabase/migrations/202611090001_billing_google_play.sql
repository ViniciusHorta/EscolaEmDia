-- Fase 5 — Assinaturas Google Play (Android).
--
-- Produtos-vaga: premium_crianca_1..5 (a loja não deixa a mesma conta Google comprar o mesmo
-- produto duas vezes, por isso cada criança Premium da família usa uma vaga diferente).
--
-- Fluxo:
--   1. O responsável pede uma oferta (billing_play_offer): o servidor escolhe a primeira vaga livre
--      da família e regista a intenção (família, criança, produto).
--   2. A app compra esse produto com obfuscatedAccountId = id da família.
--   3. A compra é verificada no servidor (API Google Play) — pela app logo a seguir à compra e pelas
--      notificações em tempo real (RTDN). billing_apply_play_subscription liga o purchaseToken à
--      criança da intenção e aplica o estado atual (idempotente, imune à ordem).
--   4. A compra só é confirmada (acknowledge) na Google depois de aplicada; sem confirmação em 3 dias
--      a Google reembolsa automaticamente.
begin;

insert into public.billing_settings(key, value, description) values
  ('store_renewal_leeway_hours', 24, 'Horas após o fim do período em que uma assinatura das lojas com renovação automática continua ativa à espera da renovação');

create table public.play_purchase_intents (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid references public.children(id) on delete set null,
  product_id text not null check (product_id ~ '^premium_crianca_[1-9][0-9]*$'),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  purchase_token text unique
);
create index play_purchase_intents_family_product_idx
  on public.play_purchase_intents(family_id, product_id, created_at desc);

alter table public.play_purchase_intents enable row level security;
revoke all on public.play_purchase_intents from public, anon, authenticated, service_role;
grant select on public.play_purchase_intents to service_role;

-- Oferta Google Play para uma criança: valida o responsável e escolhe a vaga (produto) livre.
create function public.billing_play_offer(p_actor_id uuid, p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ctx jsonb;
  v_family uuid;
  v_product text;
begin
  v_ctx := public.billing_checkout_context(p_actor_id, p_child_id);  -- mesmas regras do Stripe
  if v_ctx ? 'error' then return v_ctx; end if;
  v_family := (v_ctx->>'familyId')::uuid;
  select 'premium_crianca_' || n into v_product
    from generate_series(1, public.billing_setting('max_premium_children')) n
   where not exists (
     select 1 from public.child_subscriptions s
      where s.family_id = v_family and s.channel = 'google_play'
        and s.store_product_id = 'premium_crianca_' || n
        and s.status in ('pending','active','in_grace'))
   order by n limit 1;
  if v_product is null then return jsonb_build_object('error', 'MAX_PREMIUM_CHILDREN_REACHED'); end if;
  insert into public.play_purchase_intents(family_id, child_id, product_id, created_by)
    values (v_family, p_child_id, v_product, p_actor_id);
  return jsonb_build_object('familyId', v_family, 'childId', p_child_id, 'productId', v_product);
end;
$$;

-- O adulto pode registar compras desta família?
create function public.billing_actor_in_family(p_actor_id uuid, p_family_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members m join public.families f on f.id = m.family_id
                  where m.family_id = p_family_id and m.adult_user_id = p_actor_id
                    and m.status = 'active' and f.status = 'active')
$$;

-- Aplica o estado ATUAL de uma assinatura Google Play (purchases.subscriptionsv2.get).
-- p: {eventId, eventType, purchaseToken, linkedPurchaseToken, productId, familyId (obfuscatedExternalAccountId),
--     state, startTime, expiryTime, autoRenewing, priceMicros, currency}
-- Devolve {ok, plan, acknowledge} | {ignored} | {error: UNKNOWN_FAMILY | NO_PURCHASE_INTENT |
--   CHILD_ALREADY_PREMIUM | MAX_PREMIUM_CHILDREN_REACHED}. Com erro numa compra ativa, a função
--   Edge revoga a compra na Google (reembolso), para o responsável não pagar sem acesso.
create function public.billing_apply_play_subscription(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_token text := p->>'purchaseToken';
  v_family uuid := nullif(p->>'familyId', '')::uuid;
  v_child uuid;
  v_status text;
  v_start timestamptz := nullif(p->>'startTime', '')::timestamptz;
  v_end timestamptz := nullif(p->>'expiryTime', '')::timestamptz;
  v_renew boolean := coalesce((p->>'autoRenewing')::boolean, false);
  v_grace timestamptz;
  v_row public.child_subscriptions;
  v_linked public.child_subscriptions;
  v_intent public.play_purchase_intents;
  v_result jsonb;
begin
  select * into v_row from public.child_subscriptions
   where channel = 'google_play' and external_id = v_token for update;
  if v_row.id is not null then
    v_family := v_row.family_id; v_child := v_row.child_id;
  end if;

  v_status := case p->>'state'
    when 'SUBSCRIPTION_STATE_ACTIVE' then 'active'
    when 'SUBSCRIPTION_STATE_CANCELED' then 'active'          -- cancelada: acesso até ao fim do período
    when 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' then 'in_grace'
    when 'SUBSCRIPTION_STATE_PENDING' then null
    else 'expired' end;                                         -- ON_HOLD, PAUSED, EXPIRED, PENDING_PURCHASE_CANCELED
  if v_status = 'active' and p->>'state' = 'SUBSCRIPTION_STATE_CANCELED' then v_renew := false; end if;
  if v_status = 'active' and v_end is not null and v_end <= now() then v_status := 'expired'; end if;
  v_grace := case
    when v_status = 'active' and v_renew then v_end + make_interval(hours => public.billing_setting('store_renewal_leeway_hours'))
    when v_status = 'in_grace' then greatest(v_end, now())  -- na tolerância a Google já estende expiryTime
    else null end;
  if v_status = 'expired' then v_end := least(coalesce(v_end, now()), now()); v_renew := false; end if;

  begin
    if v_row.id is not null then
      update public.child_subscriptions
         set status = coalesce(v_status, status), auto_renew = v_renew,
             current_period_start = coalesce(v_start, current_period_start),
             current_period_end = coalesce(v_end, current_period_end), grace_until = v_grace,
             price_amount_cents = coalesce(round((p->>'priceMicros')::numeric / 10000)::integer, price_amount_cents),
             currency = coalesce(upper(p->>'currency'), currency)
       where id = v_row.id returning * into v_row;
      v_result := jsonb_build_object('ok', true);
    elsif v_family is null or not exists (select 1 from public.families where id = v_family) then
      v_result := jsonb_build_object('error', 'UNKNOWN_FAMILY');
    elsif v_status is null or v_status = 'expired' then
      v_result := jsonb_build_object('ignored', true);
    else
      -- Renovação com novo token (re-subscrição/troca): herda a criança do token anterior.
      if nullif(p->>'linkedPurchaseToken', '') is not null then
        select * into v_linked from public.child_subscriptions
         where channel = 'google_play' and external_id = p->>'linkedPurchaseToken' for update;
        if v_linked.id is not null then
          v_child := v_linked.child_id;
          update public.child_subscriptions set status = 'expired', auto_renew = false,
                 current_period_end = least(coalesce(current_period_end, now()), now()), grace_until = null
           where id = v_linked.id and status in ('pending','active','in_grace');
        end if;
      end if;
      if v_child is null then
        select * into v_intent from public.play_purchase_intents
         where family_id = v_family and product_id = p->>'productId' and purchase_token is null
         order by created_at desc limit 1 for update;
        if v_intent.id is null then raise exception using message = 'NO_PURCHASE_INTENT', errcode = 'P0001'; end if;
        update public.play_purchase_intents set purchase_token = v_token where id = v_intent.id;
        v_child := v_intent.child_id;
      end if;
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
        values (v_family, v_child, 'google_play', v_token, p->>'productId', v_status, v_renew, v_start, v_end, v_grace,
          round((p->>'priceMicros')::numeric / 10000)::integer, upper(p->>'currency'))
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
    values ((select id from public.families where id = v_family), v_child, v_row.id, 'google_play',
            coalesce(p->>'eventType', 'subscription.sync'), nullif(p->>'eventId', ''),
            (p - 'eventId' - 'eventType' - 'purchaseToken' - 'linkedPurchaseToken')
              || jsonb_build_object('result', v_result, 'subscriptionId', v_row.id))
    on conflict (source, external_event_id) where external_event_id is not null do nothing;

  if v_result ? 'ok' then
    v_result := v_result || jsonb_build_object('acknowledge', v_row.status in ('active','in_grace'),
      'childId', v_child, 'plan', case when v_child is null then null else public.child_access(v_child)->>'plan' end);
  end if;
  return v_result;
end;
$$;

create function public.billing_play_event_seen(p_event_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.billing_events where source = 'google_play' and external_event_id = p_event_id)
$$;

-- Resumo da assinatura para a área da família passa a incluir o produto (para abrir a gestão na Play Store).
create or replace function public.child_access(p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family_id uuid;
  v_sub public.child_subscriptions;
  v_plan text;
begin
  select family_id into v_family_id from public.children where id = p_child_id;
  if not found then
    raise exception using message = 'CHILD_NOT_FOUND', errcode = 'P0001';
  end if;
  perform public.billing_rebalance_family(v_family_id);
  select * into v_sub from public.child_subscriptions s
   where s.child_id = p_child_id
     and s.status in ('active','in_grace')
     and greatest(s.current_period_end, coalesce(s.grace_until, s.current_period_end)) > now()
   order by s.current_period_end desc
   limit 1;
  if v_sub.id is not null then
    v_plan := 'premium';
  elsif exists (select 1 from public.child_free_slots where child_id = p_child_id) then
    v_plan := 'free';
  else
    v_plan := 'locked';
  end if;
  return jsonb_build_object(
    'childId', p_child_id,
    'plan', v_plan,
    'subscription', case when v_sub.id is null then null else jsonb_build_object(
      'id', v_sub.id,
      'channel', v_sub.channel,
      'status', v_sub.status,
      'autoRenew', v_sub.auto_renew,
      'currentPeriodEnd', v_sub.current_period_end,
      'graceUntil', v_sub.grace_until,
      'productId', case when v_sub.channel in ('google_play','app_store') then v_sub.store_product_id end
    ) end
  );
end;
$$;

revoke all on function
  public.billing_play_offer(uuid,uuid), public.billing_actor_in_family(uuid,uuid),
  public.billing_apply_play_subscription(jsonb), public.billing_play_event_seen(text)
  from public, anon, authenticated;
grant execute on function
  public.billing_play_offer(uuid,uuid), public.billing_actor_in_family(uuid,uuid),
  public.billing_apply_play_subscription(jsonb), public.billing_play_event_seen(text)
  to service_role;

notify pgrst, 'reload schema';
commit;
