-- Testes da Fase 6 (App Store: vagas por produto e sincronização). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/billing_phase6_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('adult', gen_random_uuid()), ('stranger', gen_random_uuid()), ('family', gen_random_uuid()),
  ('a', gen_random_uuid()), ('b', gen_random_uuid()), ('c', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.plan(p text) returns text language sql as $$ select public.child_access(pg_temp.id(p))->>'plan' $$;
create function pg_temp.offer(p text) returns jsonb language sql as $$
  select public.billing_apple_offer(pg_temp.id('adult'), pg_temp.id(p)) $$;
-- Estado App Store simulado (como devolvido pela App Store Server API).
create function pg_temp.apple(p_original text, p_product text, p_status int, p_expiry interval,
  p_renew boolean default true, p_event text default null, p_grace interval default null) returns jsonb language sql as $$
  select public.billing_apply_app_store_subscription(jsonb_build_object(
    'eventId', p_event, 'eventType', 'test', 'originalTransactionId', p_original, 'transactionId', p_original || '-t',
    'productId', p_product, 'familyId', pg_temp.id('family'), 'status', p_status,
    'purchaseDate', now() + p_expiry - interval '30 days', 'expiresDate', now() + p_expiry,
    'gracePeriodExpiresDate', case when p_grace is null then null else now() + p_grace end,
    'autoRenew', p_renew, 'priceMilli', 3990, 'currency', 'EUR', 'environment', 'Sandbox')) $$;

insert into auth.users(id, email, aud, role) values
  (pg_temp.id('adult'), 'billing-test6@example.invalid', 'authenticated', 'authenticated'),
  (pg_temp.id('stranger'), 'billing-test6b@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, 2, 'owl', now() - d
  from (values ('a', interval '3 days'), ('b', interval '2 days'), ('c', interval '1 day')) x(n, d);

do $$
declare v jsonb;
begin
  -- 1. Oferta: só o responsável; primeira vaga livre.
  assert public.billing_apple_offer(pg_temp.id('stranger'), pg_temp.id('b'))->>'error' = 'CHILD_NOT_FOUND', '1a';
  assert pg_temp.offer('b')->>'productId' = 'premium_crianca_1', '1b';
  raise notice 'OK 1 — oferta escolhe premium_crianca_1';

  -- 2. Compra ativa → Premium; preço em cêntimos; vaga 1 ocupada → a próxima oferta é a 2.
  v := pg_temp.apple('orig_b', 'premium_crianca_1', 1, interval '30 days', true, 'n1');
  assert v->>'plan' = 'premium' and v->>'childId' = pg_temp.id('b')::text, '2a: ' || v::text;
  assert (select price_amount_cents from public.child_subscriptions where external_id = 'orig_b') = 399, '2b';
  assert pg_temp.offer('c')->>'productId' = 'premium_crianca_2', '2c';
  raise notice 'OK 2 — compra liga-se à criança da intenção';

  -- 3. Idempotente.
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 1, interval '30 days', true, 'n1');
  assert (select count(*) from public.child_subscriptions where external_id = 'orig_b') = 1 and public.billing_apple_event_seen('n1'), '3';
  raise notice 'OK 3 — idempotente';

  -- 4. Renovação desligada: Premium até ao fim, sem renovação.
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 1, interval '5 days', false);
  assert pg_temp.plan('b') = 'premium' and (select not auto_renew from public.child_subscriptions where external_id = 'orig_b'), '4';
  raise notice 'OK 4 — renovação desligada mantém acesso até ao fim';

  -- 5. Tolerância (4) mantém; nova tentativa de cobrança sem tolerância (3) bloqueia.
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 4, interval '-1 hour', true, null, interval '6 days');
  assert pg_temp.plan('b') = 'premium', '5a';
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 3, interval '-1 day');
  assert pg_temp.plan('b') = 'locked', '5b';
  raise notice 'OK 5 — tolerância mantém, nova tentativa sem tolerância bloqueia';

  -- 6. Reembolso pela Apple (5) → revogada.
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 1, interval '30 days');
  perform pg_temp.apple('orig_b', 'premium_crianca_1', 5, interval '30 days');
  assert pg_temp.plan('b') = 'locked' and (select status from public.child_subscriptions where external_id = 'orig_b') = 'revoked', '6';
  raise notice 'OK 6 — reembolso revoga';

  -- 7. Mesmo produto comprado de novo para OUTRA criança: o originalTransactionId repete-se e a vaga muda de criança.
  perform pg_temp.offer('a');  -- intenção nova para premium_crianca_1 (a vaga 1 está livre)
  v := pg_temp.apple('orig_b', 'premium_crianca_1', 1, interval '30 days');
  assert v->>'childId' = pg_temp.id('a')::text and pg_temp.plan('a') = 'premium' and pg_temp.plan('b') <> 'premium', '7: ' || v::text;
  raise notice 'OK 7 — recompra muda a vaga para a criança da intenção';

  -- 8. Compra sem intenção é recusada (sem reembolso possível pelo servidor: fica no histórico).
  v := pg_temp.apple('orig_x', 'premium_crianca_4', 1, interval '30 days');
  assert v->>'error' = 'NO_PURCHASE_INTENT', '8: ' || v::text;
  assert exists (select 1 from public.billing_events where source = 'app_store' and payload->'result'->>'error' = 'NO_PURCHASE_INTENT'), '8b';
  raise notice 'OK 8 — compra desconhecida recusada e registada';

  -- 9. Segunda compra para a mesma criança é recusada.
  insert into public.app_store_purchase_intents(family_id, child_id, product_id, created_by)
    values (pg_temp.id('family'), pg_temp.id('a'), 'premium_crianca_3', pg_temp.id('adult'));
  v := pg_temp.apple('orig_dup', 'premium_crianca_3', 1, interval '30 days');
  assert v->>'error' = 'CHILD_ALREADY_PREMIUM', '9: ' || v::text;
  raise notice 'OK 9 — sem assinatura duplicada';

  -- 10. Família desconhecida.
  v := public.billing_apply_app_store_subscription(jsonb_build_object('originalTransactionId', 'orig_z', 'productId', 'premium_crianca_1',
    'familyId', gen_random_uuid(), 'status', 1, 'expiresDate', now() + interval '1 day'));
  assert v->>'error' = 'UNKNOWN_FAMILY', '10: ' || v::text;
  raise notice 'OK 10 — família desconhecida';

  -- 11. Resumo inclui o produto.
  assert public.child_access(pg_temp.id('a'))->'subscription'->>'productId' = 'premium_crianca_1', '11';
  raise notice 'OK 11 — productId no resumo';
end;
$$;

select 'TODOS OS TESTES DA FASE 6 PASSARAM' as resultado;
rollback;
