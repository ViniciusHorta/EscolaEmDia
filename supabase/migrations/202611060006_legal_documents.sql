begin;

-- Documentos legais versionados (Termos de Utilização e Política de Privacidade) e registo
-- do aceite de cada responsável na versão exata que leu.
--
-- Regras:
-- * Cada publicação cria uma versão nova e imutável (número sequencial por tipo).
-- * A versão em vigor de cada tipo é a de número mais alto.
-- * requires_reacceptance = false serve para correções menores (gralhas, contactos): quem já
--   aceitou uma versão anterior continua em conformidade. Por omissão exige novo aceite.
-- * Um responsável está em conformidade num tipo se aceitou uma versão igual ou posterior à
--   última versão publicada que exige aceite.
-- * Os aceites são só de inserção: nunca se alteram nem apagam (exceto ao apagar a conta).

create table public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('terms', 'privacy')),
  version integer not null check (version >= 1),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  change_summary text check (change_summary is null or char_length(change_summary) <= 2000),
  content text not null check (char_length(btrim(content)) between 1 and 200000),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  requires_reacceptance boolean not null default true,
  published_at timestamptz not null default now(),
  unique (kind, version)
);

create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_id uuid not null references public.legal_documents(id),
  accepted_at timestamptz not null default now(),
  source text not null check (source in ('signup', 'in_app')),
  ip_address inet,
  user_agent text check (user_agent is null or char_length(user_agent) <= 512),
  unique (user_id, document_id)
);
create index legal_acceptances_document_idx on public.legal_acceptances(document_id);

-- Imutabilidade: versões publicadas e aceites não podem ser alterados.
create function public.legal_reject_mutation() returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using message = 'LEGAL_RECORD_IMMUTABLE', errcode = 'P0001';
end;
$$;
create trigger legal_documents_immutable before update or delete on public.legal_documents
  for each row execute function public.legal_reject_mutation();
create trigger legal_acceptances_immutable before update on public.legal_acceptances
  for each row execute function public.legal_reject_mutation();

alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;
revoke all on public.legal_documents, public.legal_acceptances from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Leitura
-- ---------------------------------------------------------------------------

create function public.legal_document_json(d public.legal_documents) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', d.id, 'kind', d.kind, 'version', d.version, 'title', d.title,
    'changeSummary', d.change_summary, 'content', d.content, 'contentSha256', d.content_sha256,
    'requiresReacceptance', d.requires_reacceptance, 'publishedAt', d.published_at);
$$;

-- Versões em vigor (uma por tipo), visíveis antes do registo.
create function public.legal_current_documents() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.legal_document_json(d) order by d.kind desc), '[]'::jsonb)
  from (select distinct on (kind) * from public.legal_documents order by kind, version desc) d;
$$;

-- Uma versão concreta (por exemplo, a que o responsável aceitou).
create function public.legal_document_by_id(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select public.legal_document_json(d) from public.legal_documents d where d.id = p_id;
$$;

-- Estado do responsável: versões em vigor, o que aceitou e o que falta aceitar.
create function public.legal_acceptance_status(p_user_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_current jsonb := '[]'::jsonb;
  v_pending jsonb := '[]'::jsonb;
  v_accepted jsonb := '[]'::jsonb;
  r public.legal_documents;
begin
  for r in
    select distinct on (d.kind) d.* from public.legal_documents d order by d.kind desc, d.version desc
  loop
    v_current := v_current || jsonb_build_array(public.legal_document_json(r));
    -- Última versão que exige aceite; a primeira versão exige sempre.
    if not exists (
      select 1 from public.legal_acceptances a join public.legal_documents d on d.id = a.document_id
      where a.user_id = p_user_id and d.kind = r.kind and d.version >= (
        select coalesce(max(x.version), 1) from public.legal_documents x
        where x.kind = r.kind and x.requires_reacceptance
      )
    ) then
      v_pending := v_pending || jsonb_build_array(public.legal_document_json(r));
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object('documentId', d.id, 'kind', d.kind, 'version', d.version,
      'title', d.title, 'acceptedAt', a.accepted_at, 'source', a.source) order by d.kind desc, d.version desc), '[]'::jsonb)
    into v_accepted
    from public.legal_acceptances a join public.legal_documents d on d.id = a.document_id
    where a.user_id = p_user_id;

  return jsonb_build_object('current', v_current, 'pending', v_pending, 'accepted', v_accepted);
end;
$$;

-- ---------------------------------------------------------------------------
-- Aceite
-- ---------------------------------------------------------------------------

-- Aceite na app (responsável autenticado). Só aceita as versões em vigor: aceitar uma versão
-- antiga não tem efeito jurídico útil e indicaria um cliente desatualizado.
create function public.accept_legal_documents(
  p_user_id uuid, p_document_ids uuid[], p_ip inet default null, p_user_agent text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from auth.users where id = p_user_id and email_confirmed_at is not null) then
    raise exception using message = 'AUTH_REQUIRED', errcode = 'P0001';
  end if;
  if p_document_ids is null or cardinality(p_document_ids) not between 1 and 10 then
    raise exception using message = 'INVALID_REQUEST', errcode = 'P0001';
  end if;
  foreach v_id in array p_document_ids loop
    if not exists (
      select 1 from public.legal_documents d where d.id = v_id
        and d.version = (select max(x.version) from public.legal_documents x where x.kind = d.kind)
    ) then
      raise exception using message = 'DOCUMENT_OUTDATED', errcode = 'P0001';
    end if;
    insert into public.legal_acceptances(user_id, document_id, source, ip_address, user_agent)
      values (p_user_id, v_id, 'in_app', p_ip, left(p_user_agent, 512))
      on conflict (user_id, document_id) do nothing;
  end loop;
  return public.legal_acceptance_status(p_user_id);
end;
$$;

-- Aceite no registo: a app envia em user_metadata.legal_acceptances os ids das versões que a
-- pessoa leu e aceitou no formulário. Regista-se no instante da criação da conta.
-- Ids desconhecidos ou de versões já substituídas são ignorados (a pessoa terá de aceitar na
-- app no primeiro acesso). Nunca bloqueia a criação da conta.
create function public.legal_record_signup_acceptances() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_raw jsonb := new.raw_user_meta_data -> 'legal_acceptances';
  v_item jsonb;
begin
  if v_raw is null or jsonb_typeof(v_raw) <> 'array' then return new; end if;
  begin
    for v_item in select value from jsonb_array_elements(v_raw) limit 10 loop
      if jsonb_typeof(v_item) = 'string'
        and (v_item #>> '{}') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        insert into public.legal_acceptances(user_id, document_id, accepted_at, source)
          select new.id, d.id, coalesce(new.created_at, now()), 'signup'
          from public.legal_documents d
          where d.id = (v_item #>> '{}')::uuid
            and d.version = (select max(x.version) from public.legal_documents x where x.kind = d.kind)
          on conflict (user_id, document_id) do nothing;
      end if;
    end loop;
  exception when others then
    raise warning 'legal_record_signup_acceptances: %', sqlerrm;
  end;
  return new;
end;
$$;
create trigger on_auth_user_created_legal after insert on auth.users
  for each row execute function public.legal_record_signup_acceptances();

-- ---------------------------------------------------------------------------
-- Administração (tools/admin, apenas service_role)
-- ---------------------------------------------------------------------------

create function public.admin_list_legal_documents() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.legal_document_json(d)
      || jsonb_build_object('acceptanceCount', (select count(*) from public.legal_acceptances a where a.document_id = d.id),
                            'isCurrent', d.version = (select max(x.version) from public.legal_documents x where x.kind = d.kind))
      order by d.kind desc, d.version desc), '[]'::jsonb)
  from public.legal_documents d;
$$;

create function public.admin_publish_legal_document(
  p_kind text, p_title text, p_content text, p_change_summary text default null,
  p_requires_reacceptance boolean default true
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_doc public.legal_documents;
  v_last public.legal_documents;
  v_content text := btrim(coalesce(p_content, ''));
  v_summary text := nullif(btrim(coalesce(p_change_summary, '')), '');
begin
  if p_kind is null or p_kind not in ('terms', 'privacy') then return jsonb_build_object('error', 'INVALID_KIND'); end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 160 then return jsonb_build_object('error', 'INVALID_TITLE'); end if;
  if char_length(v_content) not between 1 and 200000 then return jsonb_build_object('error', 'INVALID_CONTENT'); end if;
  if v_summary is not null and char_length(v_summary) > 2000 then return jsonb_build_object('error', 'INVALID_SUMMARY'); end if;

  -- Serializa publicações do mesmo tipo.
  perform pg_advisory_xact_lock(hashtext('legal_documents:' || p_kind));
  select * into v_last from public.legal_documents where kind = p_kind order by version desc limit 1;
  if found and v_last.content = v_content and v_last.title = btrim(p_title) then
    return jsonb_build_object('error', 'UNCHANGED');
  end if;

  insert into public.legal_documents(kind, version, title, change_summary, content, content_sha256, requires_reacceptance)
    values (p_kind, coalesce(v_last.version, 0) + 1, btrim(p_title), v_summary, v_content,
      encode(sha256(convert_to(v_content, 'UTF8')), 'hex'),
      -- A primeira versão exige sempre aceite.
      case when v_last.id is null then true else coalesce(p_requires_reacceptance, true) end)
    returning * into v_doc;
  return public.legal_document_json(v_doc);
end;
$$;

revoke all on function public.legal_document_json(public.legal_documents) from public, anon, authenticated;
revoke all on function public.legal_current_documents() from public, anon, authenticated;
revoke all on function public.legal_document_by_id(uuid) from public, anon, authenticated;
revoke all on function public.legal_acceptance_status(uuid) from public, anon, authenticated;
revoke all on function public.accept_legal_documents(uuid, uuid[], inet, text) from public, anon, authenticated;
revoke all on function public.legal_record_signup_acceptances() from public, anon, authenticated;
revoke all on function public.legal_reject_mutation() from public, anon, authenticated;
revoke all on function public.admin_list_legal_documents() from public, anon, authenticated;
revoke all on function public.admin_publish_legal_document(text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.legal_current_documents() to service_role;
grant execute on function public.legal_document_by_id(uuid) to service_role;
grant execute on function public.legal_acceptance_status(uuid) to service_role;
grant execute on function public.accept_legal_documents(uuid, uuid[], inet, text) to service_role;
grant execute on function public.admin_list_legal_documents() to service_role;
grant execute on function public.admin_publish_legal_document(text, text, text, text, boolean) to service_role;

notify pgrst, 'reload schema';
commit;
