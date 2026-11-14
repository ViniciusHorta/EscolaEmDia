-- Fase 4 — Pagamentos Web com Stripe.
--
-- Fluxo:
--   1. O responsável (PIN desbloqueado) pede um checkout para uma criança → Edge Function `billing`
--      valida com billing_checkout_context, cria/reutiliza o cliente Stripe da família e regista a
--      sessão em stripe_checkout_sessions.
--   2. O Premium só é ativado pelo webhook (`stripe-webhook`), nunca pelo regresso do browser.
--      O webhook lê sempre o estado atual da assinatura na API do Stripe e aplica-o com
--      billing_apply_stripe_subscription (idempotente, imune à ordem dos eventos).
--   3. Renovação: enquanto auto_renew, o Premium mantém-se até current_period_end + folga de
--      renovação (o Stripe cobra no fim do período e o webhook chega pouco depois).
--      past_due → in_grace com tolerância configurável; canceled/unpaid → expired.
begin;

insert into public.billing_settings(key, value, description) values
  ('stripe_renewal_leeway_hours', 48, 'Horas após o fim do período em que uma assinatura Stripe com renovação automática continua ativa à espera da cobrança'),
  ('paid_grace_days',              7, 'Dias de tolerância após falha de pagamento (assinatura past_due)');

create table public.stripe_customers (
  family_id uuid primary key references public.families(id) on delete cascade,
  customer_id text not null unique check (customer_id ~ '^cus_[A-Za-z0-9]+$'),
  created_at timestamptz not null default now()
);

create table public.stripe_checkout_sessions (
  id text primary key check (id ~ '^cs_[A-Za-z0-9_]+$'),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid references public.children(id) on delete set null,
  created_by uuid not null,
  status text not null default 'open' check (status in ('open','complete','expired')),
  subscription_id text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index stripe_checkout_sessions_child_open_idx
  on public.stripe_checkout_sessions(child_id) where status = 'open';

alter table public.stripe_customers enable row level security;
alter table public.stripe_checkout_sessions enable row level security;
revoke all on public.stripe_customers, public.stripe_checkout_sessions
  from public, anon, authenticated, service_role;
grant select on public.stripe_customers, public.stripe_checkout_sessions to service_role;

-- O adulto é membro ativo da família ativa da criança? Devolve a família ou null.
create function public.billing_actor_child_family(p_actor_id uuid, p_child_id uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select c.family_id from public.children c
    join public.families f on f.id = c.family_id and f.status = 'active'
    join public.family_members m on m.family_id = c.family_id
     and m.adult_user_id = p_actor_id and m.status = 'active'
   where c.id = p_child_id
$$;

-- Pré-condições do checkout. Devolve {error} ou o contexto para criar a sessão no Stripe.
create function public.billing_checkout_context(p_actor_id uuid, p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_family uuid;
begin
  v_family := public.billing_actor_child_family(p_actor_id, p_child_id);
  if v_family is null then return jsonb_build_object('error', 'CHILD_NOT_FOUND'); end if;
  perform public.billing_rebalance_family(v_family);
  if exists (select 1 from public.child_subscriptions
              where child_id = p_child_id and status in ('pending','active','in_grace')
                and channel <> 'manual') then
    return jsonb_build_object('error', 'CHILD_ALREADY_PREMIUM');
  end if;
  if (select count(*) from public.child_subscriptions
       where family_id = v_family and status in ('pending','active','in_grace')
         and (child_id is distinct from p_child_id))
     >= public.billing_setting('max_premium_children') then
    return jsonb_build_object('error', 'MAX_PREMIUM_CHILDREN_REACHED');
  end if;
  return jsonb_build_object(
    'familyId', v_family,
    'childId', p_child_id,
    'customerId', (select customer_id from public.stripe_customers where family_id = v_family),
    'openSessions', coalesce((select jsonb_agg(id) from public.stripe_checkout_sessions
                               where child_id = p_child_id and status = 'open' and expires_at > now()), '[]'::jsonb)
  );
end;
$$;

-- Guarda o cliente Stripe da família (o primeiro ganha numa corrida). Devolve o cliente em uso.
create function public.billing_save_stripe_customer(p_family_id uuid, p_customer_id text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stripe_customers(family_id, customer_id) values (p_family_id, p_customer_id)
    on conflict (family_id) do nothing;
  return (select customer_id from public.stripe_customers where family_id = p_family_id);
end;
$$;

create function public.billing_record_checkout(p_session_id text, p_family_id uuid, p_child_id uuid,
  p_actor_id uuid, p_expires_at timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.stripe_checkout_sessions(id, family_id, child_id, created_by, expires_at)
    values (p_session_id, p_family_id, p_child_id, p_actor_id, p_expires_at)
    on conflict (id) do nothing;
  insert into public.billing_events(family_id, child_id, source, event_type, payload)
    values (p_family_id, p_child_id, 'stripe', 'checkout.created', jsonb_build_object('sessionId', p_session_id));
end;
$$;

create function public.billing_update_checkout(p_session_id text, p_status text, p_subscription_id text)
returns void language sql security definer set search_path = '' as $$
  update public.stripe_checkout_sessions
     set status = p_status, subscription_id = coalesce(p_subscription_id, subscription_id)
   where id = p_session_id and status = 'open' and p_status in ('complete','expired')
$$;

-- Cliente Stripe para o portal de gestão. Devolve {customerId} ou {error}.
create function public.billing_portal_context(p_actor_id uuid, p_family_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_customer text;
begin
  if not exists (select 1 from public.family_members m join public.families f on f.id = m.family_id
                  where m.family_id = p_family_id and m.adult_user_id = p_actor_id
                    and m.status = 'active' and f.status = 'active') then
    return jsonb_build_object('error', 'FAMILY_NOT_FOUND');
  end if;
  select customer_id into v_customer from public.stripe_customers where family_id = p_family_id;
  if v_customer is null then return jsonb_build_object('error', 'NO_STRIPE_CUSTOMER'); end if;
  return jsonb_build_object('customerId', v_customer);
end;
$$;

create function public.billing_stripe_event_seen(p_event_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.billing_events where source = 'stripe' and external_event_id = p_event_id)
$$;

-- Aplica o estado ATUAL de uma assinatura Stripe (lido da API pelo webhook).
-- p: {eventId, eventType, subscriptionId, customerId, familyId, childId, status, periodStart, periodEnd,
--     cancelAtPeriodEnd, endedAt, amount, currency, priceId}
-- Devolve {ok, plan} | {ignored} | {error: CUSTOMER_FAMILY_MISMATCH | CHILD_ALREADY_PREMIUM | MAX_PREMIUM_CHILDREN_REACHED}.
-- Com erro, o webhook cancela a assinatura no Stripe (o pai não fica a pagar sem acesso).
create function public.billing_apply_stripe_subscription(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family uuid := nullif(p->>'familyId', '')::uuid;
  v_child uuid := nullif(p->>'childId', '')::uuid;
  v_status text;
  v_start timestamptz := nullif(p->>'periodStart', '')::timestamptz;
  v_end timestamptz := nullif(p->>'periodEnd', '')::timestamptz;
  v_ended timestamptz := nullif(p->>'endedAt', '')::timestamptz;
  v_renew boolean := not coalesce((p->>'cancelAtPeriodEnd')::boolean, false);
  v_grace timestamptz;
  v_row public.child_subscriptions;
  v_result jsonb;
begin
  if not exists (select 1 from public.stripe_customers
                  where family_id = v_family and customer_id = p->>'customerId') then
    v_result := jsonb_build_object('error', 'CUSTOMER_FAMILY_MISMATCH');
  else
    -- Perfil eliminado entretanto: a assinatura fica registada sem criança.
    if v_child is not null and not exists (select 1 from public.children where id = v_child and family_id = v_family) then
      v_child := null;
    end if;
    v_status := case p->>'status'
      when 'active' then 'active' when 'trialing' then 'active'
      when 'past_due' then 'in_grace'
      when 'incomplete' then null
      else 'expired' end;  -- canceled, unpaid, incomplete_expired, paused
    v_grace := case
      when v_status = 'in_grace' then greatest(v_end, now()) + make_interval(days => public.billing_setting('paid_grace_days'))
      when v_status = 'active' and v_renew then v_end + make_interval(hours => public.billing_setting('stripe_renewal_leeway_hours'))
      else null end;
    if v_status = 'expired' then
      v_end := least(coalesce(v_end, now()), coalesce(v_ended, now()));
      v_renew := false;
    end if;

    select * into v_row from public.child_subscriptions
     where channel = 'stripe' and external_id = p->>'subscriptionId' for update;

    begin
      if v_row.id is null then
        if v_status is null or v_status = 'expired' then
          v_result := jsonb_build_object('ignored', true);
        else
          if v_child is not null then
            -- Premium manual (teste/oferta) é substituído pela assinatura paga.
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
            values (v_family, v_child, 'stripe', p->>'subscriptionId', p->>'priceId',
              v_status, v_renew, v_start, v_end, v_grace, (p->>'amount')::integer, upper(p->>'currency'))
            returning * into v_row;
          v_result := jsonb_build_object('ok', true);
        end if;
      else
        update public.child_subscriptions
           set status = coalesce(v_status, status), auto_renew = v_renew,
               current_period_start = coalesce(v_start, current_period_start),
               current_period_end = coalesce(v_end, current_period_end),
               grace_until = v_grace,
               price_amount_cents = coalesce((p->>'amount')::integer, price_amount_cents),
               currency = coalesce(upper(p->>'currency'), currency)
         where id = v_row.id
         returning * into v_row;
        v_result := jsonb_build_object('ok', true);
      end if;
    exception
      when unique_violation then v_result := jsonb_build_object('error', 'CHILD_ALREADY_PREMIUM');
      when raise_exception then
        if sqlerrm in ('CHILD_ALREADY_PREMIUM', 'MAX_PREMIUM_CHILDREN_REACHED') then
          v_result := jsonb_build_object('error', sqlerrm);
        else raise; end if;
    end;
  end if;

  insert into public.billing_events(family_id, child_id, subscription_id, source, event_type, external_event_id, payload)
    values (case when v_result ? 'error' and v_result->>'error' = 'CUSTOMER_FAMILY_MISMATCH' then null else v_family end,
            v_child, v_row.id, 'stripe', coalesce(p->>'eventType', 'subscription.sync'), nullif(p->>'eventId', ''),
            (p - 'eventId' - 'eventType') || jsonb_build_object('result', v_result))
    on conflict (source, external_event_id) where external_event_id is not null do nothing;

  if v_child is not null and v_result ? 'ok' then
    v_result := v_result || jsonb_build_object('plan', public.child_access(v_child)->>'plan');
  end if;
  return v_result;
end;
$$;

-- Eventos do Stripe que não mexem em assinaturas (checkout expirado, etc.): só auditoria.
create function public.billing_record_stripe_event(p_event_id text, p_event_type text, p_family_id uuid,
  p_child_id uuid, p_payload jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.billing_events(family_id, child_id, source, event_type, external_event_id, payload)
  values ((select id from public.families where id = p_family_id), p_child_id, 'stripe', p_event_type, p_event_id,
          coalesce(p_payload, '{}'::jsonb))
  on conflict (source, external_event_id) where external_event_id is not null do nothing
$$;

revoke all on function
  public.billing_actor_child_family(uuid,uuid), public.billing_checkout_context(uuid,uuid),
  public.billing_save_stripe_customer(uuid,text), public.billing_record_checkout(text,uuid,uuid,uuid,timestamptz),
  public.billing_update_checkout(text,text,text), public.billing_portal_context(uuid,uuid),
  public.billing_stripe_event_seen(text), public.billing_apply_stripe_subscription(jsonb),
  public.billing_record_stripe_event(text,text,uuid,uuid,jsonb)
  from public, anon, authenticated;
grant execute on function
  public.billing_checkout_context(uuid,uuid), public.billing_save_stripe_customer(uuid,text),
  public.billing_record_checkout(text,uuid,uuid,uuid,timestamptz), public.billing_update_checkout(text,text,text),
  public.billing_portal_context(uuid,uuid), public.billing_stripe_event_seen(text),
  public.billing_apply_stripe_subscription(jsonb), public.billing_record_stripe_event(text,text,uuid,uuid,jsonb)
  to service_role;

notify pgrst, 'reload schema';
commit;
