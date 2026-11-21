begin;

-- Conteúdos da grade curricular (só para o admin).
-- Nível abaixo do tema: Disciplina › Ano › Tema › Conteúdo (ex.: Matemática › 4.º › Números › «Valor posicional»).
-- Servem para medir a cobertura do catálogo (mínimo de fichas Free e Premium por conteúdo).
-- Os responsáveis continuam a ver só os temas; nada disto sai do admin.
-- A ligação ficha ↔ conteúdo é metadado do admin: não é versionada (pode mudar sem criar versão nova).

create table public.topic_contents (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.topics(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 200),
  semester smallint check (semester in (1, 2)),
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create unique index topic_contents_name_unique on public.topic_contents(topic_id, lower(name));

create table public.worksheet_contents (
  worksheet_id uuid not null references public.worksheets(id) on delete cascade,
  content_id uuid not null references public.topic_contents(id) on delete cascade,
  primary key (worksheet_id, content_id)
);
create index worksheet_contents_content_idx on public.worksheet_contents(content_id);

alter table public.topic_contents enable row level security;
alter table public.worksheet_contents enable row level security;
revoke all on public.topic_contents, public.worksheet_contents from public, anon, authenticated, service_role;
grant select on public.topic_contents, public.worksheet_contents to service_role;

-- Todos os conteúdos, com disciplina/ano do tema e as fichas ligadas.
create function public.admin_list_contents()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'topicId', c.topic_id, 'subjectId', t.subject_id, 'schoolYear', t.school_year,
      'name', c.name, 'semester', c.semester, 'position', c.position,
      'worksheetIds', coalesce((select jsonb_agg(wc.worksheet_id) from public.worksheet_contents wc where wc.content_id = c.id), '[]'::jsonb))
    order by t.school_year, t.name, c.position, c.name), '[]'::jsonb)
  from public.topic_contents c join public.topics t on t.id = c.topic_id;
$$;

-- Criar (p_id null) ou editar um conteúdo.
create function public.admin_save_content(p_id uuid, p_topic_id uuid, p_name text, p_semester integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_name text := btrim(coalesce(p_name, '')); v_topic public.topics; v_old public.topics; v_c public.topic_contents;
begin
  if char_length(v_name) not between 1 and 200 then return jsonb_build_object('error', 'INVALID_NAME'); end if;
  if p_semester is not null and p_semester not in (1, 2) then return jsonb_build_object('error', 'INVALID_SEMESTER'); end if;
  select * into v_topic from public.topics where id = p_topic_id;
  if not found then return jsonb_build_object('error', 'TOPIC_NOT_FOUND'); end if;
  if exists(select 1 from public.topic_contents where topic_id = p_topic_id and lower(name) = lower(v_name) and id is distinct from p_id) then
    return jsonb_build_object('error', 'CONTENT_EXISTS');
  end if;
  if p_id is null then
    insert into public.topic_contents(topic_id, name, semester, position)
      values (p_topic_id, v_name, p_semester,
        coalesce((select max(position) + 1 from public.topic_contents where topic_id = p_topic_id), 0))
      returning * into v_c;
  else
    select * into v_c from public.topic_contents where id = p_id for update;
    if not found then return jsonb_build_object('error', 'CONTENT_NOT_FOUND'); end if;
    -- Com fichas ligadas, só muda para um tema da mesma disciplina e ano.
    select * into v_old from public.topics where id = v_c.topic_id;
    if (v_old.subject_id <> v_topic.subject_id or v_old.school_year <> v_topic.school_year)
      and exists(select 1 from public.worksheet_contents where content_id = p_id) then
      return jsonb_build_object('error', 'CONTENT_IN_USE');
    end if;
    update public.topic_contents set topic_id = p_topic_id, name = v_name, semester = p_semester
      where id = p_id returning * into v_c;
  end if;
  return jsonb_build_object('id', v_c.id, 'topicId', v_c.topic_id, 'name', v_c.name, 'semester', v_c.semester);
end;
$$;

-- Apagar um conteúdo (as ligações às fichas desaparecem; as fichas não mudam).
create function public.admin_delete_content(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  delete from public.topic_contents where id = p_id;
  if not found then return jsonb_build_object('error', 'CONTENT_NOT_FOUND'); end if;
  return jsonb_build_object('id', p_id);
end;
$$;

-- Importação em lote (lista das educadoras ou rascunho da grade).
-- p_items: [{ "subjectId", "schoolYear", "topicId" | "topicName", "name", "semester"? }]
-- Com «topicName», reutiliza o tema com esse nome (sem distinguir maiúsculas) ou cria-o.
-- Conteúdos que já existem no tema são ignorados. Tudo ou nada.
create function public.admin_import_contents(p_items jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare it jsonb; v_topic public.topics; v_name text; v_tname text; v_year integer; v_sem integer;
  v_topics integer := 0; v_created integer := 0; v_skipped integer := 0;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 2000 then
    return jsonb_build_object('error', 'INVALID_ITEMS');
  end if;
  for it in select value from jsonb_array_elements(p_items) loop
    v_name := btrim(coalesce(it->>'name', ''));
    v_sem := nullif(it->>'semester', '')::integer;
    if char_length(v_name) not between 1 and 200 then raise exception 'INVALID_NAME' using detail = coalesce(it->>'name', ''); end if;
    if v_sem is not null and v_sem not in (1, 2) then raise exception 'INVALID_SEMESTER'; end if;
    if it ? 'topicId' and nullif(it->>'topicId', '') is not null then
      select * into v_topic from public.topics where id = (it->>'topicId')::uuid;
      if not found then raise exception 'TOPIC_NOT_FOUND'; end if;
    else
      v_tname := btrim(coalesce(it->>'topicName', ''));
      v_year := (it->>'schoolYear')::integer;
      if char_length(v_tname) not between 1 and 120 then raise exception 'INVALID_NAME' using detail = v_tname; end if;
      if v_year is null or v_year not between 1 and 9 then raise exception 'INVALID_SCHOOL_YEAR'; end if;
      if not exists(select 1 from public.subjects where id = (it->>'subjectId')::uuid) then raise exception 'SUBJECT_NOT_FOUND'; end if;
      select * into v_topic from public.topics where subject_id = (it->>'subjectId')::uuid and school_year = v_year
        and lower(name) = lower(v_tname);
      if not found then
        insert into public.topics(subject_id, school_year, name) values ((it->>'subjectId')::uuid, v_year, v_tname)
          returning * into v_topic;
        v_topics := v_topics + 1;
      end if;
    end if;
    if exists(select 1 from public.topic_contents where topic_id = v_topic.id and lower(name) = lower(v_name)) then
      v_skipped := v_skipped + 1;
    else
      insert into public.topic_contents(topic_id, name, semester, position)
        values (v_topic.id, v_name, v_sem,
          coalesce((select max(position) + 1 from public.topic_contents where topic_id = v_topic.id), 0));
      v_created := v_created + 1;
    end if;
  end loop;
  return jsonb_build_object('topicsCreated', v_topics, 'contentsCreated', v_created, 'skipped', v_skipped);
end;
$$;

-- Define os conteúdos de uma ficha (substitui os anteriores).
-- Têm de ser da disciplina da ficha e do ano da sua versão mais recente.
create function public.admin_set_worksheet_contents(p_worksheet_id uuid, p_content_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ws public.worksheets; v_year integer; v_ids uuid[] := coalesce(p_content_ids, '{}');
begin
  select * into v_ws from public.worksheets where id = p_worksheet_id for update;
  if not found then return jsonb_build_object('error', 'WORKSHEET_NOT_FOUND'); end if;
  select school_year into v_year from public.worksheet_versions where worksheet_id = p_worksheet_id
    order by version_number desc limit 1;
  if (select count(*) from public.topic_contents c join public.topics t on t.id = c.topic_id
      where c.id = any(v_ids) and t.subject_id = v_ws.subject_id and t.school_year = v_year)
     <> (select count(distinct x) from unnest(v_ids) x) then
    return jsonb_build_object('error', 'CONTENT_MISMATCH');
  end if;
  delete from public.worksheet_contents where worksheet_id = p_worksheet_id and content_id <> all(v_ids);
  insert into public.worksheet_contents(worksheet_id, content_id)
    select p_worksheet_id, x from unnest(v_ids) x on conflict do nothing;
  return jsonb_build_object('worksheetId', p_worksheet_id, 'contentIds', to_jsonb(v_ids));
end;
$$;

revoke all on function public.admin_list_contents(), public.admin_save_content(uuid, uuid, text, integer),
  public.admin_delete_content(uuid), public.admin_import_contents(jsonb),
  public.admin_set_worksheet_contents(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.admin_list_contents(), public.admin_save_content(uuid, uuid, text, integer),
  public.admin_delete_content(uuid), public.admin_import_contents(jsonb),
  public.admin_set_worksheet_contents(uuid, uuid[]) to service_role;

notify pgrst, 'reload schema';
commit;
