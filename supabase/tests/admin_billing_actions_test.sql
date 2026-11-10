-- Testes das ações de administração de faturação. Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/admin_billing_actions_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values ('adult', gen_random_uuid()), ('family', gen_random_uuid()), ('a', gen_random_uuid()), ('b', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;

insert into auth.users(id, email, aud, role) values (pg_temp.id('adult'), 'admin-actions-test@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, 2, 'owl', now() - d
  from (values ('a', interval '2 days'), ('b', interval '1 day')) x(n, d);
select public.billing_rebalance_family(pg_temp.id('family'));

do $$
declare v jsonb; v_old integer := public.billing_setting('free_child_slots'); v_sub uuid;
begin
  -- 1. Validação.
  begin perform public.admin_set_billing_setting('nao_existe', 1); assert false, '1a';
  exception when raise_exception then assert sqlerrm = 'SETTING_NOT_FOUND', '1a: ' || sqlerrm; end;
  begin perform public.admin_set_billing_setting('max_premium_children', 6); assert false, '1b';
  exception when raise_exception then assert sqlerrm = 'SETTING_OUT_OF_RANGE', '1b: ' || sqlerrm; end;
  raise notice 'OK 1 — chave desconhecida e fora das margens';

  -- 2. Mais vagas gratuitas: a segunda criança passa de bloqueada a Free; fica registado.
  assert public.child_access(pg_temp.id('b'))->>'plan' = 'locked', '2a';
  v := public.admin_set_billing_setting('free_child_slots', v_old + 1, 'teste');
  assert (v->>'changed')::boolean and public.child_access(pg_temp.id('b'))->>'plan' = 'free', '2b: ' || v;
  assert exists (select 1 from public.billing_events where event_type = 'setting.updated' and payload->>'key' = 'free_child_slots'
    and (payload->>'to')::int = v_old + 1), '2c';
  raise notice 'OK 2 — aumentar vagas atribui logo';

  -- 3. Menos vagas: quem já tem vaga mantém-na.
  perform public.admin_set_billing_setting('free_child_slots', v_old);
  assert public.child_access(pg_temp.id('b'))->>'plan' = 'free', '3';
  raise notice 'OK 3 — reduzir vagas não retira vagas existentes';

  -- 4. Margens expostas na lista.
  assert (select (x->>'max')::int from jsonb_array_elements(public.admin_list_billing_settings()) x where x->>'key' = 'max_premium_children') = 5, '4';
  raise notice 'OK 4 — margens na lista';

  -- 5. Contexto e registo de cancelamento.
  perform public.admin_grant_premium(pg_temp.id('a'), 10, 'teste');
  select id into v_sub from public.child_subscriptions where child_id = pg_temp.id('a') and status = 'active';
  v := public.admin_subscription_context(v_sub);
  assert v->>'channel' = 'manual' and v->>'childId' = pg_temp.id('a')::text, '5a: ' || v;
  assert public.admin_subscription_context(gen_random_uuid())->>'error' = 'SUBSCRIPTION_NOT_FOUND', '5b';
  perform public.admin_log_subscription_action(v_sub, 'subscription.cancel_requested', '{"mode":"period_end"}');
  assert exists (select 1 from public.billing_events where subscription_id = v_sub and event_type = 'subscription.cancel_requested'), '5c';
  raise notice 'OK 5 — contexto e registo';

  -- 6. Permissões.
  assert not has_function_privilege('authenticated', 'public.admin_set_billing_setting(text, integer, text)', 'execute')
     and not has_function_privilege('anon', 'public.admin_subscription_context(uuid)', 'execute')
     and has_function_privilege('service_role', 'public.admin_log_subscription_action(uuid, text, jsonb)', 'execute'), '6';
  raise notice 'OK 6 — permissões';
end;
$$;

select 'TODOS OS TESTES DE ADMIN BILLING ACTIONS PASSARAM' as resultado;
rollback;
