-- Testes da visão de utilizadores do admin. Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/admin_users_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values ('adult', gen_random_uuid()), ('family', gen_random_uuid()), ('a', gen_random_uuid()), ('b', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;

insert into auth.users(id, email, aud, role) values (pg_temp.id('adult'), 'admin-users-test@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, 2, 'owl', now() - d
  from (values ('a', interval '2 days'), ('b', interval '1 day')) x(n, d);
select public.billing_rebalance_family(pg_temp.id('family'));
select public.admin_grant_premium(pg_temp.id('b'), 30, 'teste');

do $$
declare u jsonb; kids jsonb; ev jsonb;
begin
  select x into u from jsonb_array_elements(public.admin_list_users()) x where x->>'email' = 'admin-users-test@example.invalid';
  assert u is not null, '1: utilizador em falta';
  assert jsonb_array_length(u->'families') = 1 and u->'families'->0->>'role' = 'owner', '1b: ' || (u->'families');
  kids := u->'families'->0->'children';
  assert kids->0->>'name' = 'Teste a' and kids->0->>'plan' = 'free' and kids->0->>'freeSlotSince' is not null, '2: ' || (kids->0);
  assert kids->1->>'plan' = 'premium' and kids->1->'subscriptions'->0->>'channel' = 'manual'
     and kids->1->'subscriptions'->0->>'lastPaymentAt' is not null, '3: ' || (kids->1);
  raise notice 'OK 1-3 — responsável, crianças, plano e assinatura';

  ev := public.admin_family_billing_events(pg_temp.id('family'));
  assert exists (select 1 from jsonb_array_elements(ev) e where e->>'eventType' = 'subscription.granted' and e->>'childName' = 'Teste b'), '4: ' || ev;
  raise notice 'OK 4 — histórico de eventos';

  assert jsonb_array_length(public.admin_list_billing_settings()) >= 1, '5';
  assert not has_function_privilege('authenticated', 'public.admin_list_users()', 'execute')
     and not has_function_privilege('anon', 'public.admin_family_billing_events(uuid, integer)', 'execute')
     and has_function_privilege('service_role', 'public.admin_list_users()', 'execute'), '6: permissões';
  raise notice 'OK 5-6 — limites e permissões';
end;
$$;

select 'TODOS OS TESTES DE ADMIN USERS PASSARAM' as resultado;
rollback;
