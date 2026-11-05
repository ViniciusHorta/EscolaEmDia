begin;

-- Importação administrativa de fichas (ferramenta local tools/importador-exercicios).
-- Executável apenas com a chave service_role ou no SQL Editor; nunca pelas apps.
-- Cria a ficha publicada numa só transação: worksheet → versão 1 → tema → publicação.
create function public.admin_import_worksheet(
  p_subject_name text,
  p_school_year integer,
  p_topic_name text,
  p_title text,
  p_content jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_subject public.subjects;
  v_topic public.topics;
  v_topic_created boolean := false;
  v_title text := btrim(coalesce(p_title, ''));
  v_topic_name text := btrim(coalesce(p_topic_name, ''));
  v_existing record;
  v_worksheet_id uuid;
  v_version_id uuid;
begin
  if p_school_year is null or p_school_year not between 1 and 4 then
    return jsonb_build_object('error', 'INVALID_SCHOOL_YEAR');
  end if;
  if char_length(v_title) not between 1 and 160 then
    return jsonb_build_object('error', 'INVALID_TITLE');
  end if;
  if char_length(v_topic_name) not between 1 and 120 then
    return jsonb_build_object('error', 'INVALID_TOPIC');
  end if;
  if p_content is null or not public.valid_worksheet_content(p_content) then
    return jsonb_build_object('error', 'INVALID_CONTENT');
  end if;

  -- A disciplina tem de existir (evita criar disciplinas por engano de escrita).
  select * into v_subject from public.subjects where lower(name) = lower(btrim(coalesce(p_subject_name, '')));
  if not found then return jsonb_build_object('error', 'SUBJECT_NOT_FOUND'); end if;

  -- O tema é reutilizado se já existir para a disciplina e o ano; caso contrário é criado.
  select * into v_topic from public.topics
    where subject_id = v_subject.id and school_year = p_school_year and lower(name) = lower(v_topic_name);
  if not found then
    insert into public.topics(subject_id, school_year, name) values (v_subject.id, p_school_year, v_topic_name)
      returning * into v_topic;
    v_topic_created := true;
  end if;

  -- Idempotência: a mesma ficha (disciplina, ano, título e conteúdo) não é importada duas vezes.
  select w.id as worksheet_id, v.id as version_id into v_existing
    from public.worksheets w join public.worksheet_versions v on v.worksheet_id = w.id
    where w.subject_id = v_subject.id and w.title = v_title and v.school_year = p_school_year
      and v.content_json = p_content
    limit 1;
  if found then
    return jsonb_build_object('duplicate', true, 'worksheetId', v_existing.worksheet_id,
      'versionId', v_existing.version_id, 'topicId', v_topic.id, 'topicCreated', v_topic_created);
  end if;

  insert into public.worksheets(subject_id, title) values (v_subject.id, v_title) returning id into v_worksheet_id;
  insert into public.worksheet_versions(worksheet_id, version_number, school_year, content_json)
    values (v_worksheet_id, 1, p_school_year, p_content) returning id into v_version_id;
  insert into public.worksheet_version_topics(worksheet_version_id, topic_id) values (v_version_id, v_topic.id);
  update public.worksheet_versions set published_at = now() where id = v_version_id;
  update public.worksheets set status = 'published' where id = v_worksheet_id;

  return jsonb_build_object('duplicate', false, 'worksheetId', v_worksheet_id, 'versionId', v_version_id,
    'topicId', v_topic.id, 'topicCreated', v_topic_created,
    'questionCount', jsonb_array_length(p_content->'questions'));
end;
$$;

revoke all on function public.admin_import_worksheet(text,integer,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.admin_import_worksheet(text,integer,text,text,jsonb) to service_role;

notify pgrst, 'reload schema';
commit;
