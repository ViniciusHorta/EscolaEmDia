-- Testes: assinaturas a cancelar antes de eliminar a conta. Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/account_deletion_subscriptions_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values ('adult', gen_random_uuid()), ('other', gen_random_uuid()),
  ('solo', gen_random_uuid()), ('shared', gen_random_uuid()), ('a', gen_random_uuid()), ('b', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;

insert into auth.users(id, email, aud, role) values
  (pg_temp.id('adult'), 'del-subs@example.invalid', 'authenticated', 'authenticated'),
  (pg_temp.id('other'), 'del-subs2@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values
  (pg_temp.id('solo'), pg_temp.id('adult'), gen_random_uuid()),
  (pg_temp.id('shared'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values
  (pg_temp.id('solo'), pg_temp.id('adult')), (pg_temp.id('shared'), pg_temp.id('adult')), (pg_temp.id('shared'), pg_temp.id('other'));
insert into public.children(id, family_id, display_name, school_year, avatar_id) values
  (pg_temp.id('a'), pg_temp.id('solo'), 'A', 2, 'owl'), (pg_temp.id('b'), pg_temp.id('shared'), 'B', 2, 'owl');
insert into public.child_subscriptions(family_id, child_id, channel, external_id, store_product_id, status, current_period_end) values
  (pg_temp.id('solo'), pg_temp.id('a'), 'google_play', 'tok_del', 'premium_crianca_1', 'active', now() + interval '10 days'),
  (pg_temp.id('shared'), pg_temp.id('b'), 'stripe', 'sub_del', null, 'active', now() + interval '10 days');

do $$
declare v jsonb := public.account_deletion_subscriptions(pg_temp.id('adult'));
begin
  -- Só a família que vai ser apagada (a partilhada fica com o outro adulto, com a assinatura).
  assert jsonb_array_length(v) = 1 and v->0->>'channel' = 'google_play' and v->0->>'externalId' = 'tok_del', '1: ' || v::text;
  assert jsonb_array_length(public.account_deletion_subscriptions(pg_temp.id('other'))) = 0, '2';
  assert not has_function_privilege('authenticated', 'public.account_deletion_subscriptions(uuid)', 'execute'), '3';
  raise notice 'OK 1-3';
end;
$$;

select 'TODOS OS TESTES DE ACCOUNT DELETION SUBSCRIPTIONS PASSARAM' as resultado;
rollback;
