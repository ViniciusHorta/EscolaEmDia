-- Testes da Fase 1 (direitos de acesso). Corre numa transação e faz ROLLBACK no fim:
-- não deixa dados no banco.
--   tools/staging.sh test supabase/tests/billing_phase1_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('adult', gen_random_uuid()), ('family', gen_random_uuid()),
  ('a', gen_random_uuid()), ('b', gen_random_uuid()), ('c', gen_random_uuid());

create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.plan(p text) returns text language sql as $$
  select public.child_access(pg_temp.id(p))->>'plan' $$;
create function pg_temp.add_child(p text, p_age interval) returns void language sql as $$
  insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  values (pg_temp.id(p), pg_temp.id('family'), 'Teste ' || p, 2, 'fox', now() - p_age) $$;

insert into auth.users(id, email, aud, role) values (pg_temp.id('adult'), 'billing-test@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));

do $$
declare v_err text;
begin
  -- 1. Primeira criança ocupa a vaga gratuita; a segunda fica bloqueada.
  perform pg_temp.add_child('a', '3 days');
  assert pg_temp.plan('a') = 'free',   '1: A deveria ser free';
  perform pg_temp.add_child('b', '2 days');
  assert pg_temp.plan('b') = 'locked', '1: B deveria ser locked';
  raise notice 'OK 1 — vaga gratuita para a primeira criança, segunda bloqueada';

  -- 2. Premium manual para B não mexe na vaga de A.
  perform public.admin_grant_premium(pg_temp.id('b'), 30, 'teste');
  assert pg_temp.plan('b') = 'premium', '2: B deveria ser premium';
  assert pg_temp.plan('a') = 'free',    '2: A deveria continuar free';
  raise notice 'OK 2 — Premium manual';

  -- 3. Assinatura duplicada é recusada.
  begin
    perform public.admin_grant_premium(pg_temp.id('b'), 30);
    raise exception 'esperava CHILD_ALREADY_PREMIUM';
  exception when others then v_err := sqlerrm; end;
  assert v_err = 'CHILD_ALREADY_PREMIUM', '3: erro inesperado: ' || v_err;
  raise notice 'OK 3 — sem assinatura duplicada';

  -- 4. A passa a Premium → vaga libertada; nova criança C ocupa-a.
  perform public.admin_grant_premium(pg_temp.id('a'), 30);
  assert pg_temp.plan('a') = 'premium', '4: A deveria ser premium';
  assert not exists (select 1 from public.child_free_slots where child_id = pg_temp.id('a')), '4: A não deveria ter vaga';
  perform pg_temp.add_child('c', '1 day');
  assert pg_temp.plan('c') = 'free', '4: C deveria ocupar a vaga livre';
  raise notice 'OK 4 — vaga libertada ao contratar Premium e ocupada pela nova criança';

  -- 5. Fim do Premium de A sem vaga livre → A fica bloqueada.
  perform public.admin_revoke_premium(pg_temp.id('a'));
  assert pg_temp.plan('a') = 'locked', '5: A deveria ficar locked';
  assert pg_temp.plan('c') = 'free',   '5: C mantém a vaga';
  raise notice 'OK 5 — fim do Premium sem vaga livre bloqueia a criança';

  -- 6. Eliminar C (que tem a vaga) → A, bloqueada e mais antiga, ocupa-a.
  delete from public.children where id = pg_temp.id('c');
  assert pg_temp.plan('a') = 'free', '6: A deveria ocupar a vaga libertada';
  raise notice 'OK 6 — vaga libertada ao eliminar o perfil';

  -- 7. Expiração: período terminado sem tolerância → expired.
  update public.child_subscriptions set current_period_start = now() - interval '31 days',
         current_period_end = now() - interval '1 minute'
   where child_id = pg_temp.id('b') and status = 'active';
  assert pg_temp.plan('b') = 'locked', '7: B deveria ficar locked após expirar';
  assert (select status from public.child_subscriptions where child_id = pg_temp.id('b')
          order by created_at desc limit 1) = 'expired', '7: estado deveria ser expired';
  raise notice 'OK 7 — expiração automática';

  -- 8. Tolerância: período terminado mas grace_until no futuro → continua Premium.
  perform public.admin_grant_premium(pg_temp.id('b'), 30);
  update public.child_subscriptions set status = 'in_grace',
         current_period_end = now() - interval '1 hour', grace_until = now() + interval '2 days'
   where child_id = pg_temp.id('b') and status = 'active';
  assert pg_temp.plan('b') = 'premium', '8: B deveria manter Premium na tolerância';
  raise notice 'OK 8 — tolerância de pagamento';

  -- 9. Limite configurável de crianças Premium por conta.
  update public.billing_settings set value = 1 where key = 'max_premium_children';
  begin
    perform public.admin_grant_premium(pg_temp.id('a'), 30);
    raise exception 'esperava MAX_PREMIUM_CHILDREN_REACHED';
  exception when others then v_err := sqlerrm; end;
  assert v_err = 'MAX_PREMIUM_CHILDREN_REACHED', '9: erro inesperado: ' || v_err;
  raise notice 'OK 9 — limite de crianças Premium (configurável)';

  -- 10. Registo auditável.
  assert (select count(*) from public.billing_events where family_id = pg_temp.id('family')) >= 8,
    '10: eventos insuficientes';
  raise notice 'OK 10 — eventos registados: %',
    (select string_agg(event_type, ', ' order by id) from public.billing_events where family_id = pg_temp.id('family'));
end;
$$;

select 'TODOS OS TESTES DA FASE 1 PASSARAM' as resultado;
rollback;
