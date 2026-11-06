begin;

-- Gestão administrativa do catálogo (ferramenta local tools/admin).
-- Todas as funções são executáveis apenas com a chave service_role ou no SQL Editor; nunca pelas apps.
-- Regras de integridade preservadas:
--   • versões publicadas são imutáveis: editar uma ficha publicada cria uma nova versão;
--   • fichas com versões publicadas não se apagam (podem ser arquivadas);
--   • temas usados por fichas só podem ser renomeados (não mudam de disciplina/ano nem se apagam).

-- ---------------------------------------------------------------------------
-- Visão geral: disciplinas e temas com contagens de utilização.
-- ---------------------------------------------------------------------------
create function public.admin_catalogue_overview()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'subjects', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name,
        'topicCount', (select count(*) from public.topics t where t.subject_id = s.id),
        'worksheetCount', (select count(*) from public.worksheets w where w.subject_id = s.id)
      ) order by s.name) from public.subjects s), '[]'::jsonb),
    'topics', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'subjectId', t.subject_id, 'schoolYear', t.school_year, 'name', t.name,
        'worksheetCount', (select count(distinct v.worksheet_id) from public.worksheet_version_topics vt
          join public.worksheet_versions v on v.id = vt.worksheet_version_id where vt.topic_id = t.id),
        'inUse', exists(select 1 from public.worksheet_version_topics vt where vt.topic_id = t.id)
      ) order by t.school_year, t.name) from public.topics t), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------------------------
-- Disciplinas
-- ---------------------------------------------------------------------------
create function public.admin_save_subject(p_id uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_name text := btrim(coalesce(p_name, '')); v_subject public.subjects;
begin
  if char_length(v_name) not between 1 and 80 then return jsonb_build_object('error', 'INVALID_NAME'); end if;
  if exists(select 1 from public.subjects where lower(name) = lower(v_name) and id is distinct from p_id) then
    return jsonb_build_object('error', 'SUBJECT_EXISTS');
  end if;
  if p_id is null then
    insert into public.subjects(name) values (v_name) returning * into v_subject;
  else
    update public.subjects set name = v_name where id = p_id returning * into v_subject;
    if not found then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;
  end if;
  return jsonb_build_object('id', v_subject.id, 'name', v_subject.name);
end;
$$;

create function public.admin_delete_subject(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from public.topics where subject_id = p_id)
    or exists(select 1 from public.worksheets where subject_id = p_id) then
    return jsonb_build_object('error', 'SUBJECT_IN_USE');
  end if;
  delete from public.subjects where id = p_id;
  if not found then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;
  return jsonb_build_object('deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Temas
-- ---------------------------------------------------------------------------
create function public.admin_save_topic(p_id uuid, p_subject_id uuid, p_school_year integer, p_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_name text := btrim(coalesce(p_name, '')); v_topic public.topics;
begin
  if char_length(v_name) not between 1 and 120 then return jsonb_build_object('error', 'INVALID_NAME'); end if;
  if p_school_year is null or p_school_year not between 1 and 4 then return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR'); end if;
  if not exists(select 1 from public.subjects where id = p_subject_id) then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;
  if exists(select 1 from public.topics where subject_id = p_subject_id and school_year = p_school_year
      and lower(name) = lower(v_name) and id is distinct from p_id) then
    return jsonb_build_object('error', 'TOPIC_EXISTS');
  end if;
  if p_id is null then
    insert into public.topics(subject_id, school_year, name) values (p_subject_id, p_school_year, v_name) returning * into v_topic;
  else
    select * into v_topic from public.topics where id = p_id for update;
    if not found then return jsonb_build_object('error', 'TOPIC_NOT_FOUND'); end if;
    -- Um tema já usado por fichas só pode ser renomeado (as versões publicadas dependem da disciplina e do ano).
    if (v_topic.subject_id <> p_subject_id or v_topic.school_year <> p_school_year)
      and exists(select 1 from public.worksheet_version_topics where topic_id = p_id) then
      return jsonb_build_object('error', 'TOPIC_IN_USE');
    end if;
    update public.topics set subject_id = p_subject_id, school_year = p_school_year, name = v_name
      where id = p_id returning * into v_topic;
  end if;
  return jsonb_build_object('id', v_topic.id, 'subjectId', v_topic.subject_id, 'schoolYear', v_topic.school_year, 'name', v_topic.name);
end;
$$;

create function public.admin_delete_topic(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from public.worksheet_version_topics where topic_id = p_id) then
    return jsonb_build_object('error', 'TOPIC_IN_USE');
  end if;
  delete from public.topics where id = p_id;
  if not found then return jsonb_build_object('error', 'TOPIC_NOT_FOUND'); end if;
  return jsonb_build_object('deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fichas
-- ---------------------------------------------------------------------------
create function public.admin_list_worksheets()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb) from (
    select w.created_at, jsonb_build_object(
      'id', w.id, 'title', w.title, 'status', w.status, 'isSample', w.is_sample, 'createdAt', w.created_at,
      'subjectId', w.subject_id, 'subjectName', s.name,
      'versionCount', (select count(*) from public.worksheet_versions v where v.worksheet_id = w.id),
      'publishedVersionCount', (select count(*) from public.worksheet_versions v where v.worksheet_id = w.id and v.published_at is not null),
      'latest', (select jsonb_build_object(
          'versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year, 'publishedAt', v.published_at,
          'questionCount', jsonb_array_length(v.content_json->'questions'),
          'choiceCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'multiple-choice'),
          'trueFalseCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'true_false'),
          'writtenCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q where q->>'type' = 'written'),
          'topicIds', coalesce((select jsonb_agg(vt.topic_id) from public.worksheet_version_topics vt where vt.worksheet_version_id = v.id), '[]'::jsonb))
        from public.worksheet_versions v where v.worksheet_id = w.id order by v.version_number desc limit 1),
      'assignmentCount', (select count(*) from public.worksheet_assignments a
          join public.worksheet_versions v on v.id = a.worksheet_version_id where v.worksheet_id = w.id),
      'openReportCount', (select count(*) from public.question_reports r
          join public.worksheet_versions v on v.id = r.worksheet_version_id where v.worksheet_id = w.id and r.status in ('open','in_review'))
    ) as item
    from public.worksheets w join public.subjects s on s.id = w.subject_id
  ) x;
$$;

-- Ficha com o conteúdo da versão mais recente (publicada ou rascunho) e o histórico de versões.
create function public.admin_get_worksheet(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', w.id, 'title', w.title, 'status', w.status, 'isSample', w.is_sample, 'subjectId', w.subject_id,
    'versions', coalesce((select jsonb_agg(jsonb_build_object(
        'versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year, 'publishedAt', v.published_at,
        'questionCount', jsonb_array_length(v.content_json->'questions')) order by v.version_number desc)
      from public.worksheet_versions v where v.worksheet_id = w.id), '[]'::jsonb),
    'latest', (select jsonb_build_object('versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year,
        'publishedAt', v.published_at, 'content', v.content_json,
        'topicIds', coalesce((select jsonb_agg(vt.topic_id) from public.worksheet_version_topics vt where vt.worksheet_version_id = v.id), '[]'::jsonb))
      from public.worksheet_versions v where v.worksheet_id = w.id order by v.version_number desc limit 1)
  ) from public.worksheets w where w.id = p_id;
$$;

-- Cria (p_worksheet_id null) ou atualiza uma ficha.
-- • Se a versão mais recente é rascunho, é editada no lugar.
-- • Se está publicada e o conteúdo/ano/temas mudam, é criada uma nova versão (as atribuições antigas mantêm a sua).
-- • p_publish publica a versão resultante; caso contrário fica como rascunho.
create function public.admin_save_worksheet(
  p_worksheet_id uuid, p_subject_id uuid, p_school_year integer, p_topic_ids uuid[],
  p_title text, p_content jsonb, p_publish boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_topics uuid[];
  v_ws public.worksheets;
  v_latest public.worksheet_versions;
  v_version_id uuid;
  v_version_number integer;
  v_new_version boolean := false;
  v_published_now boolean := false;
begin
  if p_school_year is null or p_school_year not between 1 and 4 then return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR'); end if;
  if char_length(v_title) not between 1 and 160 then return jsonb_build_object('error', 'INVALID_TITLE'); end if;
  if p_content is null or not public.valid_worksheet_content(p_content) then return jsonb_build_object('error', 'INVALID_CONTENT'); end if;
  select coalesce(array_agg(distinct t order by t), '{}') into v_topics from unnest(coalesce(p_topic_ids, '{}'::uuid[])) t where t is not null;
  if cardinality(v_topics) = 0 then return jsonb_build_object('error', 'TOPICS_REQUIRED'); end if;
  if not exists(select 1 from public.subjects where id = p_subject_id) then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;

  if p_worksheet_id is not null then
    select * into v_ws from public.worksheets where id = p_worksheet_id for update;
    if not found then return jsonb_build_object('error', 'WORKSHEET_NOT_FOUND'); end if;
    if v_ws.subject_id <> p_subject_id and exists(select 1 from public.worksheet_versions
        where worksheet_id = v_ws.id and published_at is not null) then
      return jsonb_build_object('error', 'SUBJECT_LOCKED');
    end if;
  end if;

  if (select count(*) from public.topics where id = any(v_topics) and subject_id = p_subject_id
      and school_year = p_school_year) <> cardinality(v_topics) then
    return jsonb_build_object('error', 'TOPIC_MISMATCH');
  end if;

  if p_worksheet_id is null then
    insert into public.worksheets(subject_id, title) values (p_subject_id, v_title) returning * into v_ws;
    insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
      values (v_ws.id, 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
    insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
    v_new_version := true;
  else
    update public.worksheets set title = v_title, subject_id = p_subject_id where id = v_ws.id;
    select * into v_latest from public.worksheet_versions where worksheet_id = v_ws.id order by version_number desc limit 1 for update;
    if not found then
      -- Ficha sem versões (não deveria acontecer): cria a primeira.
      insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
        values (v_ws.id, 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
      v_new_version := true;
    elsif v_latest.published_at is null then
      update public.worksheet_versions set content_json = p_content, school_year = p_school_year where id = v_latest.id;
      delete from public.worksheet_version_topics where worksheet_version_id = v_latest.id;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_latest.id, unnest(v_topics);
      v_version_id := v_latest.id; v_version_number := v_latest.version_number;
    elsif v_latest.content_json is distinct from p_content or v_latest.school_year <> p_school_year
      or (select coalesce(array_agg(topic_id order by topic_id), '{}') from public.worksheet_version_topics
          where worksheet_version_id = v_latest.id) is distinct from v_topics then
      insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
        values (v_ws.id, v_latest.version_number + 1, p_school_year, p_content) returning id, version_number into v_version_id, v_version_number;
      insert into public.worksheet_version_topics(worksheet_version_id, topic_id) select v_version_id, unnest(v_topics);
      v_new_version := true;
    else
      -- Só mudou o título (não versionado): mantém a versão publicada atual.
      v_version_id := v_latest.id; v_version_number := v_latest.version_number;
    end if;
  end if;

  if coalesce(p_publish, false) then
    update public.worksheet_versions set published_at = now() where id = v_version_id and published_at is null;
    v_published_now := found;
    update public.worksheets set status = 'published' where id = v_ws.id;
  elsif not exists(select 1 from public.worksheet_versions where worksheet_id = v_ws.id and published_at is not null) then
    update public.worksheets set status = 'draft' where id = v_ws.id;
  end if;

  return jsonb_build_object('worksheetId', v_ws.id, 'versionId', v_version_id, 'versionNumber', v_version_number,
    'newVersion', v_new_version, 'publishedNow', v_published_now,
    'published', exists(select 1 from public.worksheet_versions where id = v_version_id and published_at is not null),
    'status', (select status from public.worksheets where id = v_ws.id));
end;
$$;

-- Publicar (volta a mostrar aos pais a última versão publicada) ou arquivar (deixa de aparecer no catálogo).
create function public.admin_set_worksheet_status(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_status not in ('published', 'archived') then return jsonb_build_object('error', 'INVALID_STATUS'); end if;
  if not exists(select 1 from public.worksheets where id = p_id) then return jsonb_build_object('error', 'WORKSHEET_NOT_FOUND'); end if;
  if p_status = 'published' and not exists(select 1 from public.worksheet_versions where worksheet_id = p_id and published_at is not null) then
    return jsonb_build_object('error', 'NO_PUBLISHED_VERSION');
  end if;
  update public.worksheets set status = p_status where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end;
$$;

-- Só fichas que nunca foram publicadas (sem atribuições nem respostas) podem ser apagadas.
create function public.admin_delete_worksheet(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.worksheets where id = p_id for update;
  if not found then return jsonb_build_object('error', 'WORKSHEET_NOT_FOUND'); end if;
  if exists(select 1 from public.worksheet_versions where worksheet_id = p_id and published_at is not null) then
    return jsonb_build_object('error', 'WORKSHEET_PUBLISHED');
  end if;
  delete from public.worksheet_version_topics where worksheet_version_id in (select id from public.worksheet_versions where worksheet_id = p_id);
  delete from public.worksheet_versions where worksheet_id = p_id;
  delete from public.worksheets where id = p_id;
  return jsonb_build_object('deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Relatos de problemas em perguntas
-- ---------------------------------------------------------------------------
create function public.admin_list_question_reports(p_status text default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb) from (
    select r.created_at, jsonb_build_object(
      'id', r.id, 'status', r.status, 'reason', r.reason, 'message', r.message, 'createdAt', r.created_at,
      'questionId', r.question_id, 'worksheetId', w.id, 'worksheetTitle', w.title, 'subjectName', s.name,
      'versionId', v.id, 'versionNumber', v.version_number, 'schoolYear', v.school_year,
      'isLatestVersion', not exists(select 1 from public.worksheet_versions n where n.worksheet_id = w.id and n.version_number > v.version_number),
      'question', (select q.value from jsonb_array_elements(v.content_json->'questions') q(value) where q.value->>'id' = r.question_id limit 1),
      'questionNumber', (select q.ordinality from jsonb_array_elements(v.content_json->'questions') with ordinality q(value, ordinality)
        where q.value->>'id' = r.question_id limit 1),
      'sameQuestionCount', (select count(*) from public.question_reports o
        where o.worksheet_version_id = r.worksheet_version_id and o.question_id = r.question_id)
    ) as item
    from public.question_reports r
      join public.worksheet_versions v on v.id = r.worksheet_version_id
      join public.worksheets w on w.id = v.worksheet_id
      join public.subjects s on s.id = w.subject_id
    where p_status is null or r.status = p_status
    order by r.created_at desc
    limit 500
  ) x;
$$;

create function public.admin_set_question_report_status(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_status not in ('open', 'in_review', 'resolved', 'dismissed') then return jsonb_build_object('error', 'INVALID_STATUS'); end if;
  update public.question_reports set status = p_status where id = p_id;
  if not found then return jsonb_build_object('error', 'REPORT_NOT_FOUND'); end if;
  return jsonb_build_object('id', p_id, 'status', p_status);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissões: apenas service_role.
-- ---------------------------------------------------------------------------
revoke all on function
  public.admin_catalogue_overview(),
  public.admin_save_subject(uuid, text), public.admin_delete_subject(uuid),
  public.admin_save_topic(uuid, uuid, integer, text), public.admin_delete_topic(uuid),
  public.admin_list_worksheets(), public.admin_get_worksheet(uuid),
  public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean),
  public.admin_set_worksheet_status(uuid, text), public.admin_delete_worksheet(uuid),
  public.admin_list_question_reports(text), public.admin_set_question_report_status(uuid, text)
from public, anon, authenticated;
grant execute on function
  public.admin_catalogue_overview(),
  public.admin_save_subject(uuid, text), public.admin_delete_subject(uuid),
  public.admin_save_topic(uuid, uuid, integer, text), public.admin_delete_topic(uuid),
  public.admin_list_worksheets(), public.admin_get_worksheet(uuid),
  public.admin_save_worksheet(uuid, uuid, integer, uuid[], text, jsonb, boolean),
  public.admin_set_worksheet_status(uuid, text), public.admin_delete_worksheet(uuid),
  public.admin_list_question_reports(text), public.admin_set_question_report_status(uuid, text)
to service_role;

notify pgrst, 'reload schema';
commit;
