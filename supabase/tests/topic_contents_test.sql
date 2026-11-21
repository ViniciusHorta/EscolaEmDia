-- Testes dos conteúdos da grade (admin). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/topic_contents_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values ('subj', gen_random_uuid()), ('other', gen_random_uuid()), ('topic', gen_random_uuid()), ('ws', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;

insert into public.subjects(id, name) values (pg_temp.id('subj'), 'Teste Conteúdos'), (pg_temp.id('other'), 'Teste Outra');
insert into public.topics(id, subject_id, school_year, name) values (pg_temp.id('topic'), pg_temp.id('subj'), 4, 'Números');
insert into public.worksheets(id, subject_id, title) values (pg_temp.id('ws'), pg_temp.id('subj'), 'Ficha teste');
insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
  values (pg_temp.id('ws'), 1, 4, '{"questions":[{"id":"q1","type":"written","prompt":"?"}]}');

do $$
declare r jsonb; c1 uuid; c2 uuid; c3 uuid; list jsonb;
begin
  r := public.admin_save_content(null, pg_temp.id('topic'), '  Valor posicional ', 1);
  c1 := (r->>'id')::uuid;
  assert r->>'name' = 'Valor posicional' and (r->>'semester')::int = 1, '1: ' || r;
  assert public.admin_save_content(null, pg_temp.id('topic'), 'VALOR POSICIONAL', null)->>'error' = 'CONTENT_EXISTS', '2: duplicado';
  assert public.admin_save_content(null, pg_temp.id('topic'), 'x', 3)->>'error' = 'INVALID_SEMESTER', '3: semestre';
  raise notice 'OK 1-3 — criar conteúdo';

  -- Importação: reutiliza o tema existente (sem distinguir maiúsculas), cria um novo e ignora repetidos.
  r := public.admin_import_contents(jsonb_build_array(
    jsonb_build_object('subjectId', pg_temp.id('subj'), 'schoolYear', 4, 'topicName', 'números', 'name', 'valor posicional'),
    jsonb_build_object('subjectId', pg_temp.id('subj'), 'schoolYear', 4, 'topicName', 'Números', 'name', 'Sequências de crescimento'),
    jsonb_build_object('subjectId', pg_temp.id('subj'), 'schoolYear', 4, 'topicName', 'Geometria', 'name', 'Sólidos – planificações', 'semester', 1)));
  assert (r->>'contentsCreated')::int = 2 and (r->>'topicsCreated')::int = 1 and (r->>'skipped')::int = 1, '4: ' || r;
  assert (select count(*) from public.topics where subject_id = pg_temp.id('subj')) = 2, '4b: temas';
  raise notice 'OK 4 — importação';

  select id into c2 from public.topic_contents where name = 'Sequências de crescimento';
  select id into c3 from public.topic_contents where name = 'Sólidos – planificações';

  -- Ligar à ficha (substitui), com validação de disciplina/ano.
  r := public.admin_set_worksheet_contents(pg_temp.id('ws'), array[c1, c2]);
  assert jsonb_array_length(r->'contentIds') = 2, '5: ' || r;
  r := public.admin_set_worksheet_contents(pg_temp.id('ws'), array[c2, c3]);
  assert (select array_agg(content_id order by content_id) from public.worksheet_contents where worksheet_id = pg_temp.id('ws'))
    = (select array_agg(x order by x) from unnest(array[c2, c3]) x), '6: substituir';
  insert into public.topics(subject_id, school_year, name) values (pg_temp.id('subj'), 3, 'Outro ano');
  perform public.admin_save_content(null, (select id from public.topics where name = 'Outro ano'), 'Do 3.º ano', null);
  assert public.admin_set_worksheet_contents(pg_temp.id('ws'),
    array[(select id from public.topic_contents where name = 'Do 3.º ano')])->>'error' = 'CONTENT_MISMATCH', '7: ano errado';
  raise notice 'OK 5-7 — ligar conteúdos às fichas';

  list := public.admin_list_contents();
  assert (select x->'worksheetIds' from jsonb_array_elements(list) x where (x->>'id')::uuid = c3) = jsonb_build_array(pg_temp.id('ws')), '8: lista';
  assert (select (x->>'schoolYear')::int from jsonb_array_elements(list) x where (x->>'id')::uuid = c3) = 4, '8b: ano';

  -- Mudar de disciplina com fichas ligadas não é permitido; apagar remove as ligações.
  insert into public.topics(subject_id, school_year, name) values (pg_temp.id('other'), 4, 'Alheio');
  assert public.admin_save_content(c3, (select id from public.topics where name = 'Alheio'), 'Sólidos', null)->>'error' = 'CONTENT_IN_USE', '9: mover';
  perform public.admin_delete_content(c3);
  assert not exists(select 1 from public.worksheet_contents where content_id = c3), '10: apagar';
  assert public.admin_delete_content(c3)->>'error' = 'CONTENT_NOT_FOUND', '10b';
  raise notice 'OK 8-10 — listar, mover e apagar';
end $$;

rollback;
