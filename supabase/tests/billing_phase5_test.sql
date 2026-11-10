-- Testes da Fase 5 (Google Play: vagas por produto e sincronização). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/billing_phase5_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('adult', gen_random_uuid()), ('stranger', gen_random_uuid()), ('family', gen_random_uuid()),
  ('a', gen_random_uuid()), ('b', gen_random_uuid()), ('c', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.plan(p text) returns text language sql as $$ select public.child_access(pg_temp.id(p))->>'plan' $$;
create function pg_temp.offer(p text) returns jsonb language sql as $$
  select public.billing_play_offer(pg_temp.id('adult'), pg_temp.id(p)) $$;
-- Estado Google Play simulado (como devolvido por subscriptionsv2.get).
create function pg_temp.play(p_token text, p_product text, p_state text, p_expiry interval,
  p_renew boolean default true, p_linked text default null, p_event text default null) returns jsonb language sql as $$
  select public.billing_apply_play_subscription(jsonb_build_object(
    'eventId', p_event, 'eventType', 'test', 'purchaseToken', p_token, 'linkedPurchaseToken', p_linked,
    'productId', p_product, 'familyId', pg_temp.id('family'), 'state', p_state,
    'startTime', now() + p_expiry - interval '30 days', 'expiryTime', now() + p_expiry,
    'autoRenewing', p_renew, 'priceMicros', 3990000, 'currency', 'EUR')) $$;

insert into auth.users(id, email, aud, role) values
  (pg_temp.id('adult'), 'billing-test5@example.invalid', 'authenticated', 'authenticated'),
  (pg_temp.id('stranger'), 'billing-test5b@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, 2, 'owl', now() - d
  from (values ('a', interval '3 days'), ('b', interval '2 days'), ('c', interval '1 day')) x(n, d);

do $$
declare v jsonb;
begin
  -- 1. Oferta: só o responsável; primeira vaga livre.
  assert public.billing_play_offer(pg_temp.id('stranger'), pg_temp.id('b'))->>'error' = 'CHILD_NOT_FOUND', '1a';
  assert pg_temp.offer('b')->>'productId' = 'premium_crianca_1', '1b';
  raise notice 'OK 1 — oferta escolhe premium_crianca_1';

  -- 2. Compra ativa → Premium; pede acknowledge; vaga 1 ocupada → a próxima oferta é a 2.
  v := pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days', true, null, 'msg_1');
  assert v->>'plan' = 'premium' and (v->>'acknowledge')::boolean and v->>'childId' = pg_temp.id('b')::text, '2a: ' || v;
  assert pg_temp.offer('c')->>'productId' = 'premium_crianca_2', '2b';
  raise notice 'OK 2 — compra liga-se à criança da intenção';

  -- 3. Idempotente: mesmo token e mesmo evento.
  perform pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days', true, null, 'msg_1');
  assert (select count(*) from public.child_subscriptions where external_id = 'tok_b') = 1 and public.billing_play_event_seen('msg_1'), '3';
  raise notice 'OK 3 — idempotente';

  -- 4. Cancelada pelo utilizador: Premium até ao fim, sem renovação.
  perform pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_CANCELED', interval '5 days', false);
  assert pg_temp.plan('b') = 'premium' and (select not auto_renew from public.child_subscriptions where external_id = 'tok_b'), '4';
  raise notice 'OK 4 — cancelada mantém acesso até ao fim';

  -- 5. Tolerância de pagamento e suspensão (on hold).
  perform pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', interval '3 days');
  assert pg_temp.plan('b') = 'premium', '5a';
  perform pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_ON_HOLD', interval '-1 day');
  assert pg_temp.plan('b') = 'locked', '5b';
  raise notice 'OK 5 — in_grace mantém, on_hold bloqueia';

  -- 6. Recuperação da suspensão (mesmo token volta a ativo).
  perform pg_temp.play('tok_b', 'premium_crianca_1', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days');
  assert pg_temp.plan('b') = 'premium', '6';
  raise notice 'OK 6 — recuperação da suspensão';

  -- 7. Re-subscrição com novo token (linkedPurchaseToken) herda a criança e expira o antigo.
  v := pg_temp.play('tok_b2', 'premium_crianca_1', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days', true, 'tok_b');
  assert v->>'childId' = pg_temp.id('b')::text and pg_temp.plan('b') = 'premium', '7a: ' || v;
  assert (select status from public.child_subscriptions where external_id = 'tok_b') = 'expired', '7b';
  raise notice 'OK 7 — token ligado herda a criança';

  -- 8. Compra sem intenção registada é recusada (a Edge revoga e reembolsa).
  v := pg_temp.play('tok_x', 'premium_crianca_4', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days');
  assert v->>'error' = 'NO_PURCHASE_INTENT', '8: ' || v;
  raise notice 'OK 8 — compra desconhecida recusada';

  -- 9. Segunda compra para a mesma criança é recusada.
  perform pg_temp.offer('b');  -- (bloqueado pela regra de checkout, mas forçamos uma intenção)
  insert into public.play_purchase_intents(family_id, child_id, product_id, created_by)
    values (pg_temp.id('family'), pg_temp.id('b'), 'premium_crianca_3', pg_temp.id('adult'));
  v := pg_temp.play('tok_dup', 'premium_crianca_3', 'SUBSCRIPTION_STATE_ACTIVE', interval '30 days');
  assert v->>'error' = 'CHILD_ALREADY_PREMIUM', '9: ' || v;
  raise notice 'OK 9 — sem assinatura duplicada';

  -- 10. Família desconhecida.
  v := public.billing_apply_play_subscription(jsonb_build_object('purchaseToken', 'tok_z', 'productId', 'premium_crianca_1',
    'familyId', gen_random_uuid(), 'state', 'SUBSCRIPTION_STATE_ACTIVE', 'expiryTime', now() + interval '1 day'));
  assert v->>'error' = 'UNKNOWN_FAMILY', '10: ' || v;
  raise notice 'OK 10 — família desconhecida';

  -- 11. Resumo inclui o produto (para abrir a gestão na Play Store).
  assert public.child_access(pg_temp.id('b'))->'subscription'->>'productId' = 'premium_crianca_1', '11';
  raise notice 'OK 11 — productId no resumo';
end;
$$;

select 'TODOS OS TESTES DA FASE 5 PASSARAM' as resultado;
rollback;
