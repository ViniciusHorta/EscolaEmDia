begin;

-- Relatos de problemas numa pergunta, feitos pelos pais durante a revisão.
-- Só a Edge Function «reviews» (service_role, via RPC) escreve aqui; os clientes não têm acesso direto.
create table public.question_reports (
  id uuid primary key default gen_random_uuid(),
  client_request_id uuid not null,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  attempt_id uuid not null references public.worksheet_attempts(id) on delete cascade,
  worksheet_version_id uuid not null references public.worksheet_versions(id),
  question_id text not null check (question_id ~ '^[A-Za-z0-9_-]{1,64}$'),
  reason text not null check (reason in ('wrong_answer','unclear','typo','inappropriate','other')),
  message text not null check (char_length(btrim(message)) between 5 and 1000),
  status text not null default 'open' check (status in ('open','in_review','resolved','dismissed')),
  created_at timestamptz not null default now(),
  -- Repetir o mesmo pedido (falha de rede) não cria um segundo relato.
  unique (reporter_id, client_request_id)
);
create index question_reports_version_question_idx on public.question_reports(worksheet_version_id, question_id);
create index question_reports_status_created_idx on public.question_reports(status, created_at);
create index question_reports_attempt_idx on public.question_reports(attempt_id);

alter table public.question_reports enable row level security;
revoke all on public.question_reports from public, anon, authenticated, service_role;

comment on table public.question_reports is
  'Problemas reportados pelos pais numa pergunta de uma ficha entregue. Escrita apenas por report_parent_question.';

create function public.report_parent_question(
  p_actor_id uuid, p_auth_session_id uuid, p_unlock_hash text,
  p_attempt_id uuid, p_question_id text, p_reason text, p_message text, p_client_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_access jsonb;
  v_attempt public.worksheet_attempts;
  v_family_id uuid;
  v_message text := btrim(coalesce(p_message, ''));
  v_report public.question_reports;
begin
  v_access := public.use_parent_unlock(p_actor_id, p_auth_session_id, p_unlock_hash, true, false);
  if v_access ? 'error' then return v_access; end if;

  if p_question_id is null or p_question_id !~ '^[A-Za-z0-9_-]{1,64}$'
    or p_reason not in ('wrong_answer','unclear','typo','inappropriate','other')
    or char_length(v_message) not between 5 and 1000 or p_client_request_id is null then
    return jsonb_build_object('error', 'INVALID_REQUEST');
  end if;

  select c.family_id into v_family_id from public.worksheet_attempts a
    join public.children c on c.id = a.child_id
    join public.families f on f.id = c.family_id
    join public.family_members m on m.family_id = f.id
    where a.id = p_attempt_id and f.status = 'active' and m.adult_user_id = p_actor_id and m.status = 'active';
  if not found then return jsonb_build_object('error', 'ATTEMPT_NOT_FOUND'); end if;
  select * into v_attempt from public.worksheet_attempts where id = p_attempt_id;

  if v_attempt.status not in ('submitted','pending_review','completed') then
    return jsonb_build_object('error', 'ATTEMPT_NOT_SUBMITTED');
  end if;
  if not exists (
    select 1 from public.worksheet_versions v, lateral jsonb_array_elements(v.content_json->'questions') q(value)
    where v.id = v_attempt.worksheet_version_id and q.value->>'id' = p_question_id
  ) then return jsonb_build_object('error', 'QUESTION_NOT_FOUND'); end if;

  -- Idempotência: o mesmo pedido devolve o relato já gravado; dados diferentes são rejeitados.
  select * into v_report from public.question_reports
    where reporter_id = p_actor_id and client_request_id = p_client_request_id;
  if found then
    if v_report.attempt_id <> p_attempt_id or v_report.question_id <> p_question_id
      or v_report.reason <> p_reason or v_report.message <> v_message then
      return jsonb_build_object('error', 'OPERATION_REUSED');
    end if;
  else
    insert into public.question_reports(client_request_id, reporter_id, family_id, child_id, attempt_id,
        worksheet_version_id, question_id, reason, message)
      values (p_client_request_id, p_actor_id, v_family_id, v_attempt.child_id, p_attempt_id,
        v_attempt.worksheet_version_id, p_question_id, p_reason, v_message)
      returning * into v_report;
    -- Auditoria sem o texto livre (pode conter dados pessoais).
    insert into public.family_audit_events(family_id, actor_id, event_type, payload)
      values (v_family_id, p_actor_id, 'question.reported', jsonb_build_object(
        'reportId', v_report.id, 'attemptId', p_attempt_id, 'questionId', p_question_id, 'reason', p_reason));
  end if;

  return jsonb_build_object('reportId', v_report.id, 'questionId', v_report.question_id,
    'reason', v_report.reason, 'status', v_report.status, 'createdAt', v_report.created_at);
end;
$$;

revoke all on function public.report_parent_question(uuid,uuid,text,uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.report_parent_question(uuid,uuid,text,uuid,text,text,text,uuid) to service_role;

notify pgrst, 'reload schema';
commit;
