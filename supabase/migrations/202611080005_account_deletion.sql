begin;

-- Eliminação da conta do responsável (RGPD art. 17.º; Google Play e App Store exigem-na na app).
--
-- Fluxo: a Edge Function `account` valida a sessão e uma reautenticação recente, chama
-- delete_account_data() e, por fim, apaga o utilizador em auth.users (auth.admin.deleteUser).
--
-- Regras:
-- * Uma família em que o responsável é o único adulto ativo é apagada por inteiro: perfis
--   infantis, PINs, sessões, fichas atribuídas, tentativas, respostas, revisões e relatos.
-- * Numa família com outros adultos ativos, a família continua; só sai o membro. As autorias
--   que apontavam para a conta apagada (criou a família, atribuiu, reviu, autorizou) ficam a null.
-- * O catálogo de fichas e os documentos legais publicados não são dados pessoais e ficam.
-- * Os aceites legais, PIN do responsável e sessões de desbloqueio já se apagam em cascata
--   com auth.users.

-- Substitui a chave estrangeira de (tabela, colunas) mantendo o nome. A procura é feita
-- pelas colunas porque os nomes gerados podem ter sido truncados a 63 caracteres.
create function pg_temp.replace_fk(p_table regclass, p_columns text[], p_target text, p_action text)
returns void language plpgsql as $$
declare
  v_name text;
begin
  select c.conname into strict v_name
  from pg_constraint c
  where c.conrelid = p_table and c.contype = 'f'
    and array(select a.attname::text from unnest(c.conkey) with ordinality k(attnum, pos)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
              order by k.pos) = p_columns;
  execute format('alter table %s drop constraint %I', p_table, v_name);
  execute format('alter table %s add constraint %I foreign key (%s) references %s on delete %s',
    p_table, v_name,
    (select string_agg(quote_ident(col), ', ') from unnest(p_columns) col),
    p_target, p_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Referências a auth.users que impediam apagar o utilizador.
-- ---------------------------------------------------------------------------

alter table public.families alter column created_by drop not null;
alter table public.child_sessions alter column authorized_by drop not null;
alter table public.worksheet_assignments alter column assigned_by drop not null;
alter table public.answer_reviews alter column reviewed_by drop not null;
alter table public.answer_review_events alter column changed_by drop not null;

select pg_temp.replace_fk('public.families', '{created_by}', 'auth.users(id)', 'set null');
select pg_temp.replace_fk('public.family_members', '{adult_user_id}', 'auth.users(id)', 'cascade');
select pg_temp.replace_fk('public.child_sessions', '{authorized_by}', 'auth.users(id)', 'set null');
select pg_temp.replace_fk('public.worksheet_assignments', '{assigned_by}', 'auth.users(id)', 'set null');
select pg_temp.replace_fk('public.answer_reviews', '{reviewed_by}', 'auth.users(id)', 'set null');
select pg_temp.replace_fk('public.answer_review_events', '{changed_by}', 'auth.users(id)', 'set null');

-- ---------------------------------------------------------------------------
-- 2. Dados das crianças: apagar a criança (ou a família) apaga todo o histórico.
-- ---------------------------------------------------------------------------

select pg_temp.replace_fk('public.worksheet_assignments', '{child_id}', 'public.children(id)', 'cascade');
select pg_temp.replace_fk('public.worksheet_attempts', '{child_id}', 'public.children(id)', 'cascade');
select pg_temp.replace_fk('public.worksheet_attempts', '{assignment_id,child_id,worksheet_version_id}',
  'public.worksheet_assignments(id, child_id, worksheet_version_id)', 'cascade');
select pg_temp.replace_fk('public.answers', '{attempt_id}', 'public.worksheet_attempts(id)', 'cascade');
select pg_temp.replace_fk('public.sync_operations', '{attempt_id}', 'public.worksheet_attempts(id)', 'cascade');
select pg_temp.replace_fk('public.answer_reviews', '{answer_id}', 'public.answers(id)', 'cascade');
select pg_temp.replace_fk('public.answer_review_events', '{answer_review_id}', 'public.answer_reviews(id)', 'cascade');

-- ---------------------------------------------------------------------------
-- 3. Apagar os dados da conta. Idempotente: repetir depois de uma falha é seguro.
-- ---------------------------------------------------------------------------

create function public.delete_account_data(p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_family uuid;
  v_families_deleted integer := 0;
  v_families_left integer := 0;
  v_children_deleted integer := 0;
  v_count integer;
begin
  if p_actor_id is null or not exists (select 1 from auth.users where id = p_actor_id) then
    return jsonb_build_object('error', 'AUTH_REQUIRED');
  end if;

  -- Bloqueia as famílias envolvidas por ordem estável para evitar deadlocks com outro
  -- adulto que apague a conta ao mesmo tempo.
  for v_family in
    select f.id from public.families f
    where f.created_by = p_actor_id
       or exists (select 1 from public.family_members m
                  where m.family_id = f.id and m.adult_user_id = p_actor_id)
    order by f.id
    for update
  loop
    if exists (select 1 from public.family_members m
               where m.family_id = v_family and m.status = 'active'
                 and m.adult_user_id <> p_actor_id) then
      delete from public.family_members
        where family_id = v_family and adult_user_id = p_actor_id;
      insert into public.family_audit_events(family_id, actor_id, event_type)
        values (v_family, null, 'member.account_deleted');
      v_families_left := v_families_left + 1;
    else
      select count(*) into v_count from public.children where family_id = v_family;
      v_children_deleted := v_children_deleted + v_count;
      delete from public.families where id = v_family;
      v_families_deleted := v_families_deleted + 1;
    end if;
  end loop;

  -- O resto (relatos de perguntas feitos pela conta, aceites legais, PIN e desbloqueios)
  -- apaga-se em cascata quando a Edge Function apagar o utilizador em auth.users.
  return jsonb_build_object(
    'familiesDeleted', v_families_deleted,
    'familiesLeft', v_families_left,
    'childrenDeleted', v_children_deleted);
end;
$$;

revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;

notify pgrst, 'reload schema';
commit;
