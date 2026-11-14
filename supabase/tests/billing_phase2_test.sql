-- Testes da Fase 2 (limites Free e catálogo Free/Premium). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/billing_phase2_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('adult', gen_random_uuid()), ('family', gen_random_uuid()),
  ('a', gen_random_uuid()), ('b', gen_random_uuid()), ('c', gen_random_uuid()),
  ('wf1', gen_random_uuid()), ('wf2', gen_random_uuid()), ('wp', gen_random_uuid()), ('wx', gen_random_uuid()),
  ('vf1', gen_random_uuid()), ('vf2', gen_random_uuid()), ('vp', gen_random_uuid()), ('vx', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;

-- Tema/ano reais do catálogo para cumprir as regras de publicação.
create temp table t_topic as
  select id as topic_id, subject_id, school_year from public.topics where archived_at is null order by id limit 1;

create function pg_temp.content(n integer) returns jsonb language sql as $$
  select jsonb_build_object('questions', (select jsonb_agg(jsonb_build_object('id','q'||i,'type','written','prompt','Pergunta '||i))
    from generate_series(1, n) i)) $$;

-- Cria ficha + versão (rascunho), liga o tema e publica.
create function pg_temp.worksheet(p_w text, p_v text, p_tier text, p_questions integer) returns void language plpgsql as $$
begin
  insert into public.worksheets(id, subject_id, title, status, access_tier)
    select pg_temp.id(p_w), subject_id, 'Teste billing ' || p_w, 'published', p_tier from t_topic;
  insert into public.worksheet_versions(id, worksheet_id, version_number, school_year, content_json)
    select pg_temp.id(p_v), pg_temp.id(p_w), 1, school_year, pg_temp.content(p_questions) from t_topic;
  insert into public.worksheet_version_topics select pg_temp.id(p_v), topic_id from t_topic;
  update public.worksheet_versions set published_at = now() where id = pg_temp.id(p_v);
end $$;

create function pg_temp.assign(p_child text, p_version text) returns uuid language sql as $$
  insert into public.worksheet_assignments(child_id, worksheet_version_id, assigned_by, client_request_id)
  values (pg_temp.id(p_child), pg_temp.id(p_version), pg_temp.id('adult'), gen_random_uuid()) returning id $$;

create function pg_temp.err(j jsonb) returns text language sql as $$ select coalesce(j->>'error', 'OK') $$;

insert into auth.users(id, email, aud, role) values (pg_temp.id('adult'), 'billing-test2@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id, created_at)
  select pg_temp.id(n), pg_temp.id('family'), 'Teste ' || n, (select school_year from t_topic), 'owl', now() - d
  from (values ('a', interval '3 days'), ('b', interval '2 days'), ('c', interval '1 day')) x(n, d);
select public.admin_grant_premium(pg_temp.id('c'), 30, 'teste fase 2');

do $$
declare v_err text; v_a1 uuid; v_access jsonb;
begin
  assert public.child_access(pg_temp.id('a'))->>'plan' = 'free',    'setup: A free';
  assert public.child_access(pg_temp.id('b'))->>'plan' = 'locked',  'setup: B locked';
  assert public.child_access(pg_temp.id('c'))->>'plan' = 'premium', 'setup: C premium';

  -- 1. Tier e limite de questões.
  perform pg_temp.worksheet('wf1', 'vf1', 'free', 3);
  perform pg_temp.worksheet('wf2', 'vf2', 'free', 6);
  perform pg_temp.worksheet('wp',  'vp',  'premium', 8);
  begin
    perform pg_temp.worksheet('wx', 'vx', 'free', 7);
    raise exception 'esperava FREE_WORKSHEET_TOO_MANY_QUESTIONS';
  exception when others then v_err := sqlerrm; end;
  assert v_err = 'FREE_WORKSHEET_TOO_MANY_QUESTIONS', '1a: ' || v_err;
  begin
    perform public.admin_set_worksheet_tier(pg_temp.id('wp'), 'free');
    raise exception 'esperava FREE_WORKSHEET_TOO_MANY_QUESTIONS';
  exception when others then v_err := sqlerrm; end;
  assert v_err = 'FREE_WORKSHEET_TOO_MANY_QUESTIONS', '1b: ' || v_err;
  assert (select access_tier from public.worksheet_catalogue where version_id = pg_temp.id('vf1')) = 'free', '1c: view sem tier';
  raise notice 'OK 1 — ficha Free com mais de 6 questões recusada (publicar e mudar tier)';

  -- 2. Limite diário do responsável (criança Free).
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf1'))) = 'OK', '2a';
  v_a1 := pg_temp.assign('a', 'vf1');
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf2'))) = 'DAILY_ASSIGNMENT_LIMIT_REACHED', '2b';
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vp'))) = 'PREMIUM_WORKSHEET_REQUIRED', '2c';
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('b'), pg_temp.id('vf1'))) = 'CHILD_PLAN_LOCKED', '2d';
  raise notice 'OK 2 — responsável: 1 ficha/dia, só Free, criança bloqueada recusada';

  -- 3. Ficha retirada antes de iniciar não conta; depois de iniciada, conta.
  update public.worksheet_assignments set status = 'withdrawn' where id = v_a1;
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf2'))) = 'OK', '3a: retirada não iniciada não conta';
  insert into public.worksheet_attempts(assignment_id, child_id, worksheet_version_id, attempt_number)
    values (v_a1, pg_temp.id('a'), pg_temp.id('vf1'), 1);
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf2'))) = 'DAILY_ASSIGNMENT_LIMIT_REACHED', '3b: retirada iniciada conta';
  raise notice 'OK 3 — ficha retirada só conta se a criança a iniciou';

  -- 4. Limite diário da criança (novas ou repetidas).
  assert public.child_attempts_today(pg_temp.id('a')) = 1, '4a';
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('a'), pg_temp.id('vf2'))) = 'DAILY_ATTEMPT_LIMIT_REACHED', '4b';
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('a'), pg_temp.id('vf1'))) = 'DAILY_ATTEMPT_LIMIT_REACHED', '4c: repetição também conta';
  raise notice 'OK 4 — criança: 1 ficha/dia, nova ou repetida';

  -- 5. Criança Free não inicia ficha Premium; criança bloqueada não inicia nada.
  update public.worksheet_attempts set started_at = now() - interval '1 day' where child_id = pg_temp.id('a');
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('a'), pg_temp.id('vp'))) = 'PREMIUM_WORKSHEET_UNAVAILABLE', '5a';
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('b'), pg_temp.id('vf1'))) = 'CHILD_PLAN_LOCKED', '5b';
  raise notice 'OK 5 — Free só inicia fichas Free; locked não inicia';

  -- 6. Novo dia: fichas de ontem não gastam o limite de hoje.
  update public.worksheet_assignments set assigned_at = now() - interval '1 day' where child_id = pg_temp.id('a');
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf2'))) = 'OK', '6a';
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('a'), pg_temp.id('vf1'))) = 'OK', '6b';
  raise notice 'OK 6 — limites reiniciam no dia seguinte';

  -- 7. Premium: sem limites.
  perform pg_temp.assign('c', 'vf1'); perform pg_temp.assign('c', 'vf2'); perform pg_temp.assign('c', 'vp');
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('c'), pg_temp.id('vp'))) = 'OK', '7a';
  insert into public.worksheet_attempts(assignment_id, child_id, worksheet_version_id, attempt_number)
    select id, child_id, worksheet_version_id, 1 from public.worksheet_assignments where child_id = pg_temp.id('c');
  assert pg_temp.err(public.billing_check_new_attempt(pg_temp.id('c'), pg_temp.id('vp'))) = 'OK', '7b';
  raise notice 'OK 7 — Premium sem limites';

  -- 8. Resumo para a UI.
  v_access := public.child_daily_access(pg_temp.id('a'));
  assert v_access->>'catalogue' = 'free' and (v_access->>'attemptLimit')::int = 1 and (v_access->>'assignmentLimit')::int = 1, '8a: ' || v_access;
  v_access := public.child_daily_access(pg_temp.id('c'));
  assert v_access->>'catalogue' = 'all' and v_access->'attemptLimit' = 'null'::jsonb and (v_access->>'attemptsToday')::int = 3, '8b: ' || v_access;
  assert public.child_daily_access(pg_temp.id('b'))->>'catalogue' = 'none', '8c';
  raise notice 'OK 8 — child_daily_access';

  -- 9. Limites configuráveis.
  update public.worksheet_assignments set assigned_at = now() where child_id = pg_temp.id('a');
  update public.billing_settings set value = 2 where key = 'free_daily_assignments';
  assert pg_temp.err(public.billing_check_new_assignment(pg_temp.id('a'), pg_temp.id('vf2'))) = 'OK', '9a';
  update public.billing_settings set value = 7 where key = 'free_max_questions';
  perform pg_temp.worksheet('wx', 'vx', 'free', 7);
  raise notice 'OK 9 — limites lidos de billing_settings';

  -- 10. Dia comercial em Lisboa.
  assert (public.billing_day_start() at time zone 'Europe/Lisbon')::time = '00:00', '10';
  raise notice 'OK 10 — dia começa à meia-noite de Lisboa';
end;
$$;

select 'TODOS OS TESTES DA FASE 2 PASSARAM' as resultado;
rollback;
