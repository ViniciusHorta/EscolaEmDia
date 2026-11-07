begin;
-- O responsável decide, ao disponibilizar a ficha, onde a criança responde às perguntas abertas:
--   'typed' → escreve a resposta na app;  'paper' → resolve no caderno e assinala que terminou.
-- A criança deixa de escolher: só lhe é apresentado (e só é aceite) o modo definido na atribuição.
-- Atribuições já existentes ficam com 'typed' (respostas 'paper' já gravadas continuam válidas para revisão).

alter table public.worksheet_assignments
  add column written_answer_mode text not null default 'typed'
  check (written_answer_mode in ('typed','paper'));

drop function public.assign_worksheet_to_child(uuid,uuid,text,uuid,uuid,uuid);
create function public.assign_worksheet_to_child(
  p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_child_id uuid,p_version_id uuid,p_request_id uuid,
  p_written_answer_mode text default 'typed'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb; v_child public.children; v_version public.worksheet_versions;
  v_assignment public.worksheet_assignments; v_family_id uuid;
begin
  if p_written_answer_mode is null or p_written_answer_mode not in ('typed','paper') then
    return jsonb_build_object('error','INVALID_REQUEST');
  end if;
  v_access := public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
  if v_access ? 'error' then return v_access; end if;
  select family_id into v_family_id from public.children where id=p_child_id;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  perform 1 from public.families where id=v_family_id and status='active' for share;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  perform 1 from public.family_members where family_id=v_family_id and adult_user_id=p_actor_id and status='active' for share;
  if not found then return jsonb_build_object('error','CHILD_NOT_FOUND'); end if;
  select * into v_child from public.children where id=p_child_id for update;
  select * into v_assignment from public.worksheet_assignments where assigned_by=p_actor_id and client_request_id=p_request_id;
  if found then
    if v_assignment.child_id<>p_child_id or v_assignment.worksheet_version_id<>p_version_id
      or v_assignment.written_answer_mode<>p_written_answer_mode then
      return jsonb_build_object('error','REQUEST_CONFLICT');
    end if;
  else
    select v.* into v_version from public.worksheet_versions v join public.worksheets w on w.id=v.worksheet_id
      where v.id=p_version_id and v.published_at is not null and w.status='published' for share of v,w;
    if not found then return jsonb_build_object('error','WORKSHEET_NOT_FOUND'); end if;
    if v_version.school_year<>v_child.school_year then return jsonb_build_object('error','SCHOOL_YEAR_MISMATCH'); end if;
    if exists(select 1 from public.worksheet_assignments where child_id=p_child_id and worksheet_version_id=p_version_id and status='active') then
      return jsonb_build_object('error','ASSIGNMENT_ALREADY_ACTIVE');
    end if;
    insert into public.worksheet_assignments(child_id,worksheet_version_id,assigned_by,client_request_id,written_answer_mode)
      values(p_child_id,p_version_id,p_actor_id,p_request_id,p_written_answer_mode) returning * into v_assignment;
    insert into public.family_audit_events(family_id,actor_id,event_type,payload)
      values(v_family_id,p_actor_id,'worksheet.assigned',jsonb_build_object('assignmentId',v_assignment.id,'childId',p_child_id,
        'worksheetVersionId',p_version_id,'writtenAnswerMode',p_written_answer_mode));
  end if;
  return jsonb_build_object('id',v_assignment.id,'childId',v_assignment.child_id,'worksheetVersionId',v_assignment.worksheet_version_id,
    'assignedAt',v_assignment.assigned_at,'status',v_assignment.status,'writtenAnswerMode',v_assignment.written_answer_mode);
end;
$$;
revoke all on function public.assign_worksheet_to_child(uuid,uuid,text,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.assign_worksheet_to_child(uuid,uuid,text,uuid,uuid,uuid,text) to service_role;

create or replace function public.child_attempt_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select jsonb_build_object(
  'id',a.id,'attemptNumber',a.attempt_number,'assignmentId',a.assignment_id,'childId',a.child_id,'worksheetVersionId',a.worksheet_version_id,
  'status',a.status,'startedAt',a.started_at,'writable',a.status='in_progress' and assignment.status='active',
  'writtenAnswerMode',assignment.written_answer_mode,
  'title',w.title,'subjectName',s.name,
  'instructions',coalesce(v.content_json->>'instructions',''),
  'text',coalesce(v.content_json->>'text',''),'audioText',coalesce(v.content_json->>'audioText',''),
  'questions',coalesce((select jsonb_agg(
    jsonb_build_object('id',q.value->>'id','type',q.value->>'type','prompt',q.value->>'prompt') ||
      case when q.value->>'type'='multiple-choice' then jsonb_build_object('options',(
        select jsonb_agg(jsonb_build_object('id',o.value->>'id','text',o.value->>'text') order by o.ordinality)
        from jsonb_array_elements(q.value->'options') with ordinality o(value,ordinality)
      )) else '{}'::jsonb end order by q.ordinality)
    from jsonb_array_elements(v.content_json->'questions') with ordinality q(value,ordinality)), '[]'::jsonb),
  'answers',coalesce((select jsonb_agg(jsonb_build_object('id',answer.id,'questionId',answer.question_id,
    'answer',answer.value_json,'revision',answer.revision,'updatedAt',answer.updated_at) order by answer.question_id)
    from public.answers answer where answer.attempt_id=a.id),'[]'::jsonb)
 ) from public.worksheet_attempts a
 join public.worksheet_assignments assignment on assignment.id=a.assignment_id
 join public.worksheet_versions v on v.id=a.worksheet_version_id
 join public.worksheets w on w.id=v.worksheet_id join public.subjects s on s.id=w.subject_id
 where a.id=p_attempt_id;
$$;
revoke all on function public.child_attempt_payload(uuid) from public,anon,authenticated,service_role;

create or replace function public.save_child_answer(p_token_hash text,p_attempt_id uuid,p_question_id text,
 p_operation_id uuid,p_request_hash text,p_base_revision integer,p_answer jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_child_id uuid;v_attempt public.worksheet_attempts;
 v_assignment public.worksheet_assignments;v_answer public.answers;v_operation public.sync_operations;
 v_question jsonb;v_mode text;v_result jsonb;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 v_child_id:=(v_session->'child'->>'id')::uuid;
 select assignment.* into v_assignment from public.worksheet_assignments assignment
  join public.worksheet_attempts attempt on attempt.assignment_id=assignment.id
  where attempt.id=p_attempt_id and attempt.child_id=v_child_id for share of assignment;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 select * into v_attempt from public.worksheet_attempts where id=p_attempt_id and child_id=v_child_id for update;
 select * into v_operation from public.sync_operations where id=p_operation_id;
 if found then
  if v_operation.attempt_id<>p_attempt_id or v_operation.operation_type<>'save_answer' or v_operation.request_hash<>p_request_hash then
   return jsonb_build_object('error','OPERATION_REUSED');
  end if;
  return v_operation.result_json;
 end if;
 if v_attempt.status<>'in_progress' then return jsonb_build_object('error','ATTEMPT_READ_ONLY');end if;
 if v_assignment.status<>'active' then return jsonb_build_object('error','ASSIGNMENT_WITHDRAWN');end if;
 select q.value into v_question from public.worksheet_versions v,
  lateral jsonb_array_elements(v.content_json->'questions') q(value)
  where v.id=v_attempt.worksheet_version_id and q.value->>'id'=p_question_id;
 if not found then return jsonb_build_object('error','QUESTION_NOT_FOUND');end if;
 if jsonb_typeof(p_answer) is distinct from 'object' or jsonb_typeof(p_answer->'mode') is distinct from 'string' then
  return jsonb_build_object('error','INVALID_ANSWER');end if;
 v_mode:=p_answer->>'mode';
 if v_mode='unanswered' then
  if p_answer<>jsonb_build_object('mode','unanswered') then return jsonb_build_object('error','INVALID_ANSWER');end if;
 elsif v_mode='multiple-choice' then
  if v_question->>'type'<>'multiple-choice' or jsonb_typeof(p_answer->'selectedOptionId') is distinct from 'string'
   or exists(select 1 from jsonb_object_keys(p_answer) k where k not in ('mode','selectedOptionId'))
   or not exists(select 1 from jsonb_array_elements(v_question->'options') o where o->>'id'=p_answer->>'selectedOptionId') then
   return jsonb_build_object('error','INVALID_ANSWER');end if;
 elsif v_mode='true_false' then
  if v_question->>'type'<>'true_false' or jsonb_typeof(p_answer->'value') is distinct from 'boolean'
   or exists(select 1 from jsonb_object_keys(p_answer) k where k not in ('mode','value')) then
   return jsonb_build_object('error','INVALID_ANSWER');end if;
 elsif v_mode='typed' then
  if v_assignment.written_answer_mode<>'typed' then return jsonb_build_object('error','INVALID_ANSWER');end if;
  if v_question->>'type'<>'written' or jsonb_typeof(p_answer->'text') is distinct from 'string'
   or char_length(p_answer->>'text')>5000 or exists(select 1 from jsonb_object_keys(p_answer) k where k not in ('mode','text')) then
   return jsonb_build_object('error','INVALID_ANSWER');end if;
 elsif v_mode='paper' then
  if v_assignment.written_answer_mode<>'paper' then return jsonb_build_object('error','INVALID_ANSWER');end if;
  if v_question->>'type'<>'written' or p_answer<>jsonb_build_object('mode','paper') then return jsonb_build_object('error','INVALID_ANSWER');end if;
 else return jsonb_build_object('error','INVALID_ANSWER');end if;
 select * into v_answer from public.answers where attempt_id=p_attempt_id and question_id=p_question_id;
 if p_base_revision is null or p_base_revision<0 or coalesce(v_answer.revision,0)<>p_base_revision then
  return jsonb_build_object('error','ANSWER_REVISION_CONFLICT','currentRevision',coalesce(v_answer.revision,0));
 end if;
 if v_answer.id is null then
  insert into public.answers(attempt_id,question_id,answer_type,value_json)
    values(p_attempt_id,p_question_id,v_mode,p_answer) returning * into v_answer;
 else
  update public.answers set answer_type=v_mode,value_json=p_answer,revision=revision+1,updated_at=now()
    where id=v_answer.id returning * into v_answer;
 end if;
 v_result:=jsonb_build_object('answerId',v_answer.id,'revision',v_answer.revision,'syncStatus','confirmed','updatedAt',v_answer.updated_at);
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_operation_id,p_attempt_id,'save_answer',p_request_hash,v_result);
 return v_result;
end;
$$;

notify pgrst,'reload schema';
commit;
