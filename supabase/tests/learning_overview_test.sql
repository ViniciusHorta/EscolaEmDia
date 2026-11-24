-- Testes da Visão de Aprendizagem (get_parent_child_learning). Transação com ROLLBACK.
--   tools/local.sh test supabase/tests/learning_overview_test.sql
begin;

-- O desbloqueio parental não é o objeto destes testes (é reposto pelo ROLLBACK).
create or replace function public.use_parent_unlock(p_actor_id uuid,p_auth_session_id uuid,p_token_hash text,
  p_touch boolean default false,p_revoke boolean default false)
returns jsonb language sql as $$ select '{}'::jsonb $$;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids select n, gen_random_uuid() from unnest(array['adult','family','child','mat','por','tm','tp',
  'wm','wp','vm','vp','am','ap']) n;
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.learn(p_period text, p_subject uuid default null) returns jsonb language sql as $$
  select public.get_parent_child_learning(pg_temp.id('adult'), gen_random_uuid(), 'x', pg_temp.id('child'), p_period, p_subject) $$;
create function pg_temp.axis(p jsonb, p_id uuid) returns jsonb language sql as $$
  select a from jsonb_array_elements(p->'axes') a where a->>'id' = p_id::text $$;
create function pg_temp.attempt(p_version text, p_assignment text, p_ago interval, p_answers jsonb) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid(); k text; v jsonb;
begin
  insert into public.worksheet_attempts(id, assignment_id, child_id, worksheet_version_id, status, started_at, submitted_at, attempt_number)
  values (v_id, pg_temp.id(p_assignment), pg_temp.id('child'), pg_temp.id(p_version), 'completed', now() - p_ago, now() - p_ago,
    (select count(*) + 1 from public.worksheet_attempts where assignment_id = pg_temp.id(p_assignment)));
  for k, v in select * from jsonb_each(p_answers) loop
    insert into public.answers(attempt_id, question_id, answer_type, value_json)
    values (v_id, k, v->>'type', v->'value');
    if v ? 'review' then
      insert into public.answer_reviews(answer_id, classification, reviewed_by)
      select id, v->>'review', pg_temp.id('adult') from public.answers where attempt_id = v_id and question_id = k;
    end if;
  end loop;
  return v_id;
end $$;

insert into auth.users(id, email, aud, role) values (pg_temp.id('adult'), 'learning-test@example.invalid', 'authenticated', 'authenticated');
insert into public.families(id, created_by, creation_request_id) values (pg_temp.id('family'), pg_temp.id('adult'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values (pg_temp.id('family'), pg_temp.id('adult'));
insert into public.children(id, family_id, display_name, school_year, avatar_id)
values (pg_temp.id('child'), pg_temp.id('family'), 'Teste', 4, 'fox');

insert into public.subjects(id, name) values (pg_temp.id('mat'), 'T Matemática ' || pg_temp.id('mat')), (pg_temp.id('por'), 'T Português ' || pg_temp.id('por'));
insert into public.topics(id, subject_id, school_year, name) values
  (pg_temp.id('tm'), pg_temp.id('mat'), 4, 'Frações'), (pg_temp.id('tp'), pg_temp.id('por'), 4, 'Leitura');
insert into public.worksheets(id, subject_id, title, status) values
  (pg_temp.id('wm'), pg_temp.id('mat'), 'Ficha M', 'published'), (pg_temp.id('wp'), pg_temp.id('por'), 'Ficha P', 'published');
insert into public.worksheet_versions(id, worksheet_id, version_number, school_year, content_json) values
  (pg_temp.id('vm'), pg_temp.id('wm'), 1, 4, '{"questions":[
     {"id":"q1","type":"multiple-choice","prompt":"?","options":[{"id":"a","text":"A"},{"id":"b","text":"B"}],"correctAnswer":"a"},
     {"id":"q2","type":"multiple-choice","prompt":"?","options":[{"id":"a","text":"A"},{"id":"b","text":"B"}],"correctAnswer":"a"}]}'),
  (pg_temp.id('vp'), pg_temp.id('wp'), 1, 4, '{"questions":[
     {"id":"w1","type":"written","prompt":"?"},{"id":"w2","type":"written","prompt":"?"},{"id":"w3","type":"written","prompt":"?"},
     {"id":"q1","type":"multiple-choice","prompt":"?","options":[{"id":"a","text":"A"},{"id":"b","text":"B"}],"correctAnswer":"a"}]}');
insert into public.worksheet_version_topics values (pg_temp.id('vm'), pg_temp.id('tm')), (pg_temp.id('vp'), pg_temp.id('tp'));
update public.worksheet_versions set published_at = now() - interval '100 days' where id in (pg_temp.id('vm'), pg_temp.id('vp'));
insert into public.worksheet_assignments(id, child_id, worksheet_version_id, assigned_by, client_request_id) values
  (pg_temp.id('am'), pg_temp.id('child'), pg_temp.id('vm'), pg_temp.id('adult'), gen_random_uuid()),
  (pg_temp.id('ap'), pg_temp.id('child'), pg_temp.id('vp'), pg_temp.id('adult'), gen_random_uuid());

select pg_temp.attempt('vm', 'am', '40 days', '{"q1":{"type":"multiple-choice","value":{"selectedOptionId":"b"}}}');
select pg_temp.attempt('vm', 'am', '10 days', '{"q1":{"type":"multiple-choice","value":{"selectedOptionId":"a"}},
                                                "q2":{"type":"multiple-choice","value":{"selectedOptionId":"b"}}}');
select pg_temp.attempt('vm', 'am', '5 days',  '{"q1":{"type":"multiple-choice","value":{"selectedOptionId":"a"}},
                                                "q2":{"type":"multiple-choice","value":{"selectedOptionId":"a"}}}');
select pg_temp.attempt('vp', 'ap', '3 days',  '{"w1":{"type":"typed","value":{"text":"sim"},"review":"correct"},
                                                "w2":{"type":"typed","value":{"text":"mais ou menos"},"review":"partially_correct"},
                                                "w3":{"type":"typed","value":{"text":"por rever"}}}');

do $$
declare r jsonb; m jsonb; p jsonb;
begin
  -- 1. Gratuito, 30 dias, por disciplina.
  r := pg_temp.learn('30d');
  assert r->>'plan' <> 'premium', '1: esperava plano não Premium: ' || r;
  assert (r->>'completedAttempts')::int = 3, '1: completedAttempts=' || (r->>'completedAttempts');
  m := pg_temp.axis(r, pg_temp.id('mat')); p := pg_temp.axis(r, pg_temp.id('por'));
  -- Prática conta as duas tentativas (4 exercícios); desempenho só a mais recente (2/2).
  assert (m->>'attempts')::int = 2 and (m->>'exercises')::int = 4, '1: prática Mat ' || m;
  assert (m->>'correct')::int = 2 and (m->>'incorrect')::int = 0, '1: desempenho Mat ' || m;
  -- Escrita revista correta/parcial, escrita por rever = pendente, escolha sem resposta = incorreta.
  assert (p->>'exercises')::int = 4 and (p->>'correct')::int = 1 and (p->>'partial')::int = 1
     and (p->>'pending')::int = 1 and (p->>'incorrect')::int = 1, '1: Port ' || p;
  assert m->'previous' = 'null'::jsonb, '1: Gratuito não tem período anterior';
  raise notice 'OK 1 — contagens por disciplina (Gratuito, 30 dias)';

  -- 2. Gratuito não pode pedir outros períodos nem temas.
  assert pg_temp.learn('7d')->>'error' = 'PREMIUM_REQUIRED', '2: 7d';
  assert pg_temp.learn('30d', pg_temp.id('mat'))->>'error' = 'PREMIUM_REQUIRED', '2: temas';
  assert pg_temp.learn('1y')->>'error' = 'INVALID_REQUEST', '2: período inválido';
  raise notice 'OK 2 — limites do plano Gratuito';

  -- 3. Premium: período anterior (30–60 dias) usa a tentativa de há 40 dias.
  perform public.admin_grant_premium(pg_temp.id('child'), 30, 'teste');
  r := pg_temp.learn('30d');
  m := pg_temp.axis(r, pg_temp.id('mat'));
  assert r->>'plan' = 'premium', '3: plano';
  assert (m->'previous'->>'incorrect')::int = 2 and (m->'previous'->>'correct')::int = 0, '3: anterior ' || m;
  raise notice 'OK 3 — período anterior no Premium';

  -- 4. Premium, 7 dias: só a tentativa de há 5 dias em Mat.
  m := pg_temp.axis(pg_temp.learn('7d'), pg_temp.id('mat'));
  assert (m->>'attempts')::int = 1 and (m->>'exercises')::int = 2 and (m->>'correct')::int = 2, '4: ' || m;
  raise notice 'OK 4 — 7 dias';

  -- 5. Premium, por tema.
  r := pg_temp.learn('30d', pg_temp.id('mat'));
  assert r->'subject'->>'id' = pg_temp.id('mat')::text, '5: disciplina';
  assert jsonb_array_length(r->'axes') = 1, '5: eixos ' || r;
  assert (pg_temp.axis(r, pg_temp.id('tm'))->>'exercises')::int = 4, '5: tema';
  raise notice 'OK 5 — radar por tema';

  -- 6. Ano escolar: sem período anterior.
  assert pg_temp.axis(pg_temp.learn('year'), pg_temp.id('mat'))->'previous' = 'null'::jsonb, '6: ano';
  raise notice 'OK 6 — ano escolar sem comparação';
end $$;

rollback;
