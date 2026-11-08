-- Testes da Fase 4 (Stripe: checkout e sincronização de assinaturas). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/billing_phase4_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('adult', gen_random_uuid()), ('stranger', gen_random_uuid()), ('family', gen_random_uuid()),
  ('a', gen_random_uuid()), ('b', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.plan(p text) returns text language sql as $$ select public.child_access(pg_temp.id(p))->>'plan' $$;
-- Assinatura Stripe simulada para a criança p_child.
create function pg_temp.sub(p_sub text, p_child text, p_status text, p_end interval,
  p_cancel boolean default false, p_event text default null) returns jsonb language sql as $$
  select public.billing_apply_stripe_subscription(jsonb_build_object(
    'eventId', coalesce(p_event, 'evt_' || md5(random()::text)), 'eventType', 'customer.subscription.updated',
    'subscriptionId', p_sub, 'customerId', 'cus_TESTE4', 'familyId', pg_temp.id('family'),
    'childId', pg_temp.id(p_child), 'status', p_status,
    'periodStart', now() + p_end - interval '30 days', 'periodEnd', now() + p_end,
    'cancelAtPeriodEnd', p_cancel, 'amount', 399, 'currency', 'eur', 'priceId', 'price_teste')) $$;

insert into auth.users(id, email, aud, role) values
  (pg_temp.id('adult'), 'billing-test4@example.invalid', 'authenticated', 'authenticated'),
  (pg_temp.id('stranger'), 'billing-test4b@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, 2, 'owl', now() - d
  from (values ('a', interval '2 days'), ('b', interval '1 day')) x(n, d);

do $$
declare v jsonb;
begin
  assert pg_temp.plan('a') = 'free' and pg_temp.plan('b') = 'locked', 'setup';

  -- 1. Contexto do checkout: só membros da família; sem cliente Stripe ainda.
  assert public.billing_checkout_context(pg_temp.id('stranger'), pg_temp.id('b'))->>'error' = 'CHILD_NOT_FOUND', '1a';
  v := public.billing_checkout_context(pg_temp.id('adult'), pg_temp.id('b'));
  assert v->>'familyId' = pg_temp.id('family')::text and v->'customerId' = 'null'::jsonb, '1b: ' || v;
  raise notice 'OK 1 — checkout só para o responsável da família';

  -- 2. Cliente Stripe: o primeiro guardado ganha.
  assert public.billing_save_stripe_customer(pg_temp.id('family'), 'cus_TESTE4') = 'cus_TESTE4', '2a';
  assert public.billing_save_stripe_customer(pg_temp.id('family'), 'cus_OUTRO') = 'cus_TESTE4', '2b';
  perform public.billing_record_checkout('cs_test_teste4', pg_temp.id('family'), pg_temp.id('b'), pg_temp.id('adult'), now() + interval '30 minutes');
  assert public.billing_checkout_context(pg_temp.id('adult'), pg_temp.id('b'))->'openSessions' = '["cs_test_teste4"]'::jsonb, '2c';
  raise notice 'OK 2 — cliente por família e sessões abertas';

  -- 3. Pagamento confirmado → Premium; a vaga Free de A mantém-se.
  v := pg_temp.sub('sub_B', 'b', 'active', interval '30 days', false, 'evt_dup');
  assert v->>'plan' = 'premium', '3a: ' || v;
  assert pg_temp.plan('a') = 'free', '3b';
  assert public.billing_stripe_event_seen('evt_dup'), '3c';
  raise notice 'OK 3 — assinatura ativa dá Premium';

  -- 4. Mesmo evento outra vez é inofensivo (estado atual reaplicado).
  v := pg_temp.sub('sub_B', 'b', 'active', interval '30 days', false, 'evt_dup');
  assert (select count(*) from public.child_subscriptions where external_id = 'sub_B') = 1, '4';
  raise notice 'OK 4 — idempotente';

  -- 5. Fim do período com renovação automática: continua Premium durante a folga.
  perform pg_temp.sub('sub_B', 'b', 'active', interval '-1 hour');
  assert pg_temp.plan('b') = 'premium', '5';
  raise notice 'OK 5 — folga de renovação';

  -- 6. Falha de pagamento → in_grace (continua Premium); cancelada → expira e fica locked.
  perform pg_temp.sub('sub_B', 'b', 'past_due', interval '-1 hour');
  assert pg_temp.plan('b') = 'premium' and
    (select status from public.child_subscriptions where external_id = 'sub_B') = 'in_grace', '6a';
  perform pg_temp.sub('sub_B', 'b', 'canceled', interval '-1 hour');
  assert pg_temp.plan('b') = 'locked', '6b';
  raise notice 'OK 6 — tolerância e cancelamento';

  -- 7. Cancelar no fim do período: Premium até ao fim, sem folga, auto_renew = false.
  perform pg_temp.sub('sub_B2', 'b', 'active', interval '10 days', true);
  assert pg_temp.plan('b') = 'premium' and
    (select not auto_renew and grace_until is null from public.child_subscriptions where external_id = 'sub_B2'), '7';
  raise notice 'OK 7 — cancelamento no fim do período';

  -- 8. Segunda assinatura paga para a mesma criança é recusada (o webhook cancela-a).
  v := pg_temp.sub('sub_B3', 'b', 'active', interval '30 days');
  assert v->>'error' = 'CHILD_ALREADY_PREMIUM', '8: ' || v;
  assert public.billing_checkout_context(pg_temp.id('adult'), pg_temp.id('b'))->>'error' = 'CHILD_ALREADY_PREMIUM', '8b';
  raise notice 'OK 8 — sem assinatura duplicada';

  -- 9. Premium manual é substituído pela assinatura paga.
  perform public.admin_grant_premium(pg_temp.id('a'), 30, 'teste');
  v := pg_temp.sub('sub_A', 'a', 'active', interval '30 days');
  assert v->>'plan' = 'premium', '9a: ' || v;
  assert (select status from public.child_subscriptions where child_id = pg_temp.id('a') and channel = 'manual') = 'revoked', '9b';
  raise notice 'OK 9 — manual substituído pelo Stripe';

  -- 10. Cliente de outra família é recusado.
  v := public.billing_apply_stripe_subscription(jsonb_build_object('subscriptionId', 'sub_X', 'customerId', 'cus_OUTRO',
    'familyId', pg_temp.id('family'), 'childId', pg_temp.id('a'), 'status', 'active', 'periodEnd', now() + interval '1 day'));
  assert v->>'error' = 'CUSTOMER_FAMILY_MISMATCH', '10: ' || v;
  raise notice 'OK 10 — cliente/família validados';

  -- 11. Portal só com cliente e para membros.
  assert public.billing_portal_context(pg_temp.id('adult'), pg_temp.id('family'))->>'customerId' = 'cus_TESTE4', '11a';
  assert public.billing_portal_context(pg_temp.id('stranger'), pg_temp.id('family'))->>'error' = 'FAMILY_NOT_FOUND', '11b';
  raise notice 'OK 11 — portal de gestão';
end;
$$;

select 'TODOS OS TESTES DA FASE 4 PASSARAM' as resultado;
rollback;
