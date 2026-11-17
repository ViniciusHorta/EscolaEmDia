-- Testes: vários responsáveis por família (convites). Transação com ROLLBACK.
--   SUPABASE_YES=1 tools/staging.sh test supabase/tests/family_invitations_test.sql
begin;

create temp table t_ids(name text primary key, id uuid not null);
insert into t_ids values
  ('owner', gen_random_uuid()), ('partner', gen_random_uuid()), ('stranger', gen_random_uuid()),
  ('busy', gen_random_uuid()), ('empty', gen_random_uuid()), ('nopin', gen_random_uuid()),
  ('fam', gen_random_uuid()), ('busyfam', gen_random_uuid()), ('emptyfam', gen_random_uuid()),
  ('kid', gen_random_uuid()), ('busykid', gen_random_uuid());
create function pg_temp.id(p text) returns uuid language sql as $$ select id from t_ids where name = p $$;
create function pg_temp.tok(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'utf8')), 'hex') $$;
-- Executa e devolve 'OK' ou a mensagem do erro (sem abortar a transação).
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'OK'; exception when others then return sqlerrm; end; $$;

insert into auth.users(id, email, aud, role, email_confirmed_at) values
  (pg_temp.id('owner'), 'inv-owner@example.invalid', 'authenticated', 'authenticated', now()),
  (pg_temp.id('partner'), 'inv-partner@example.invalid', 'authenticated', 'authenticated', now()),
  (pg_temp.id('stranger'), 'inv-stranger@example.invalid', 'authenticated', 'authenticated', now()),
  (pg_temp.id('busy'), 'inv-busy@example.invalid', 'authenticated', 'authenticated', now()),
  (pg_temp.id('empty'), 'inv-empty@example.invalid', 'authenticated', 'authenticated', now()),
  (pg_temp.id('nopin'), 'inv-nopin@example.invalid', 'authenticated', 'authenticated', now());
insert into public.adult_pin_credentials(adult_user_id, pin_hash, salt)
  select id, repeat('a', 64), repeat('b', 32) from t_ids
  where name in ('owner', 'partner', 'stranger', 'busy', 'empty');
insert into public.families(id, created_by, creation_request_id) values
  (pg_temp.id('fam'), pg_temp.id('owner'), gen_random_uuid()),
  (pg_temp.id('busyfam'), pg_temp.id('busy'), gen_random_uuid()),
  (pg_temp.id('emptyfam'), pg_temp.id('empty'), gen_random_uuid());
insert into public.family_members(family_id, adult_user_id) values
  (pg_temp.id('fam'), pg_temp.id('owner')), (pg_temp.id('busyfam'), pg_temp.id('busy')),
  (pg_temp.id('emptyfam'), pg_temp.id('empty'));
insert into public.children(id, family_id, display_name, school_year, avatar_id) values
  (pg_temp.id('kid'), pg_temp.id('fam'), 'Kid', 2, 'owl'),
  (pg_temp.id('busykid'), pg_temp.id('busyfam'), 'Busy', 2, 'fox');

do $$
declare v jsonb; v_inv uuid;
begin
  -- 1. Convidar normaliza o email e devolve um convite pendente de 7 dias.
  v := public.family_invite_adult(pg_temp.id('owner'), pg_temp.id('fam'), '  INV-Partner@Example.invalid ', pg_temp.tok('p1'));
  assert v->>'email' = 'inv-partner@example.invalid' and v->>'status' = 'pending', '1: ' || v::text;
  assert (v->>'expiresAt')::timestamptz between now() + interval '6 days 23 hours' and now() + interval '7 days 1 minute', '1b';

  -- 2. Só responsáveis da família convidam; email inválido; já é responsável.
  assert pg_temp.err(format('select public.family_invite_adult(%L, %L, %L, %L)', pg_temp.id('stranger'), pg_temp.id('fam'), 'x@y.pt', pg_temp.tok('x'))) = 'FAMILY_NOT_FOUND', '2a';
  assert pg_temp.err(format('select public.family_invite_adult(%L, %L, %L, %L)', pg_temp.id('owner'), pg_temp.id('fam'), 'sem-arroba', pg_temp.tok('x'))) = 'INVALID_REQUEST', '2b';
  assert pg_temp.err(format('select public.family_invite_adult(%L, %L, %L, %L)', pg_temp.id('owner'), pg_temp.id('fam'), 'inv-owner@example.invalid', pg_temp.tok('x'))) = 'ALREADY_MEMBER', '2c';

  -- 3. Reenviar substitui o convite anterior (o token antigo deixa de valer).
  v := public.family_invite_adult(pg_temp.id('owner'), pg_temp.id('fam'), 'inv-partner@example.invalid', pg_temp.tok('p2'));
  assert (select count(*) from public.family_invitations where family_id = pg_temp.id('fam') and status = 'pending') = 1, '3a';
  assert public.family_invitation_preview(pg_temp.tok('p1'))->>'status' = 'invalid', '3b';
  v := public.family_invitation_preview(pg_temp.tok('p2'));
  assert v->>'status' = 'pending' and v->>'invitedBy' = 'inv-owner@example.invalid', '3c: ' || v::text;
  assert (v->>'accountExists')::boolean, '3d';

  -- 4. Aceitar: email tem de coincidir; sem PIN não dá.
  assert pg_temp.err(format('select public.family_accept_invitation(%L, %L)', pg_temp.id('stranger'), pg_temp.tok('p2'))) = 'INVITATION_EMAIL_MISMATCH', '4a';
  assert pg_temp.err(format('select public.family_accept_invitation(%L, %L)', pg_temp.id('nopin'), pg_temp.tok('p2'))) = 'ADULT_SETUP_REQUIRED', '4b';
  v := public.family_accept_invitation(pg_temp.id('partner'), pg_temp.tok('p2'));
  assert v->>'familyId' = pg_temp.id('fam')::text, '4c';
  assert exists (select 1 from public.family_members where family_id = pg_temp.id('fam') and adult_user_id = pg_temp.id('partner') and status = 'active'), '4d';
  -- Idempotente para o mesmo adulto; não reutilizável por outro.
  assert public.family_accept_invitation(pg_temp.id('partner'), pg_temp.tok('p2'))->>'familyId' = pg_temp.id('fam')::text, '4e';
  assert public.family_invitation_preview(pg_temp.tok('p2'))->>'status' = 'accepted', '4f';

  -- 5. Lista: dois responsáveis, nenhum convite pendente.
  v := public.family_list_members(pg_temp.id('partner'), pg_temp.id('fam'));
  assert jsonb_array_length(v->'members') = 2 and jsonb_array_length(v->'invitations') = 0, '5: ' || v::text;
  assert pg_temp.err(format('select public.family_list_members(%L, %L)', pg_temp.id('stranger'), pg_temp.id('fam'))) = 'FAMILY_NOT_FOUND', '5b';

  -- 6. Quem já tem família com crianças não pode aceitar.
  perform public.family_invite_adult(pg_temp.id('partner'), pg_temp.id('fam'), 'inv-busy@example.invalid', pg_temp.tok('b1'));
  assert pg_temp.err(format('select public.family_accept_invitation(%L, %L)', pg_temp.id('busy'), pg_temp.tok('b1'))) = 'ALREADY_IN_FAMILY', '6';

  -- 7. Quem tem uma família vazia aceita, e essa família é fechada.
  perform public.family_invite_adult(pg_temp.id('owner'), pg_temp.id('fam'), 'inv-empty@example.invalid', pg_temp.tok('e1'));
  perform public.family_accept_invitation(pg_temp.id('empty'), pg_temp.tok('e1'));
  assert (select status from public.families where id = pg_temp.id('emptyfam')) = 'closed', '7a';
  assert (select status from public.family_members where family_id = pg_temp.id('emptyfam') and adult_user_id = pg_temp.id('empty')) = 'left', '7b';

  -- 8. Limite de 4: 3 ativos + 1 pendente (busy) = 4.
  assert pg_temp.err(format('select public.family_invite_adult(%L, %L, %L, %L)', pg_temp.id('owner'), pg_temp.id('fam'), 'quinto@example.invalid', pg_temp.tok('q'))) = 'MEMBER_LIMIT', '8a';
  -- Cancelar liberta a vaga; cancelar duas vezes dá erro.
  select id into v_inv from public.family_invitations where token_hash = pg_temp.tok('b1');
  perform public.family_cancel_invitation(pg_temp.id('owner'), pg_temp.id('fam'), v_inv);
  assert pg_temp.err(format('select public.family_cancel_invitation(%L, %L, %L)', pg_temp.id('owner'), pg_temp.id('fam'), v_inv)) = 'INVITATION_INVALID', '8b';
  assert pg_temp.err(format('select public.family_accept_invitation(%L, %L)', pg_temp.id('busy'), pg_temp.tok('b1'))) = 'INVITATION_INVALID', '8c';
  perform public.family_invite_adult(pg_temp.id('owner'), pg_temp.id('fam'), 'quarto@example.invalid', pg_temp.tok('q4'));
  assert not (public.family_invitation_preview(pg_temp.tok('q4'))->>'accountExists')::boolean, '8d';

  -- 9. Convite expirado.
  update public.family_invitations set expires_at = now() - interval '1 minute' where token_hash = pg_temp.tok('q4');
  assert public.family_invitation_preview(pg_temp.tok('q4'))->>'status' = 'expired', '9a';
  assert (public.family_list_members(pg_temp.id('owner'), pg_temp.id('fam'))->'invitations'->0->>'expired')::boolean, '9b';

  -- 10. Remover e sair; nunca o último.
  v := public.family_remove_member(pg_temp.id('owner'), pg_temp.id('fam'), pg_temp.id('partner'));
  assert v->>'status' = 'removed', '10a';
  assert pg_temp.err(format('select public.family_list_members(%L, %L)', pg_temp.id('partner'), pg_temp.id('fam'))) = 'FAMILY_NOT_FOUND', '10b';
  assert pg_temp.err(format('select public.family_remove_member(%L, %L, %L)', pg_temp.id('owner'), pg_temp.id('fam'), pg_temp.id('partner'))) = 'MEMBER_NOT_FOUND', '10c';
  assert public.family_remove_member(pg_temp.id('owner'), pg_temp.id('fam'), pg_temp.id('owner'))->>'status' = 'left', '10d';
  assert pg_temp.err(format('select public.family_remove_member(%L, %L, %L)', pg_temp.id('empty'), pg_temp.id('fam'), pg_temp.id('empty'))) = 'LAST_MEMBER', '10e';

  -- 11. Um removido pode voltar com novo convite.
  perform public.family_invite_adult(pg_temp.id('empty'), pg_temp.id('fam'), 'inv-partner@example.invalid', pg_temp.tok('p3'));
  perform public.family_accept_invitation(pg_temp.id('partner'), pg_temp.tok('p3'));
  assert (select status from public.family_members where family_id = pg_temp.id('fam') and adult_user_id = pg_temp.id('partner')) = 'active', '11';

  -- 12. Sem acesso direto do cliente.
  assert not has_function_privilege('authenticated', 'public.family_accept_invitation(uuid,text)', 'execute'), '12a';
  assert not has_function_privilege('anon', 'public.family_invitation_preview(text)', 'execute'), '12b';
  assert not has_table_privilege('authenticated', 'public.family_invitations', 'select'), '12c';
  raise notice 'OK 1-12';
end;
$$;

-- 13. Anti-spam: 10 convites por família em 24 h.
do $$
begin
  -- Completa 10 convites criados hoje (reenvios ao mesmo email também contam).
  while (select count(*) from public.family_invitations where family_id = pg_temp.id('fam')) < 10 loop
    perform public.family_invite_adult(pg_temp.id('empty'), pg_temp.id('fam'), 'spam@example.invalid',
      pg_temp.tok('s' || gen_random_uuid()));
  end loop;
  assert pg_temp.err(format('select public.family_invite_adult(%L, %L, %L, %L)', pg_temp.id('empty'), pg_temp.id('fam'), 'spam@example.invalid', pg_temp.tok('s99'))) = 'RATE_LIMITED', '13';
  raise notice 'OK 13';
end;
$$;

select 'TODOS OS TESTES DE FAMILY INVITATIONS PASSARAM' as resultado;
rollback;
