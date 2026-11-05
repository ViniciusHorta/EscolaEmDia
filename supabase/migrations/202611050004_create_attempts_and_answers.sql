begin;
alter table public.worksheet_assignments add constraint worksheet_assignments_identity_unique unique(id,child_id,worksheet_version_id);
create table public.worksheet_attempts (
 id uuid primary key default gen_random_uuid(),
 assignment_id uuid not null,
 child_id uuid not null references public.children(id),
 worksheet_version_id uuid not null references public.worksheet_versions(id),
 status text not null default 'in_progress' check(status in ('in_progress','submitted','pending_review','completed','abandoned')),
 started_at timestamptz not null default now(),submitted_at timestamptz,result_viewed_at timestamptz,
 foreign key(assignment_id,child_id,worksheet_version_id)
   references public.worksheet_assignments(id,child_id,worksheet_version_id)
);
create unique index worksheet_attempts_one_in_progress on public.worksheet_attempts(assignment_id) where status='in_progress';
create index worksheet_attempts_child_submitted_idx on public.worksheet_attempts(child_id,submitted_at desc);
create index worksheet_attempts_assignment_started_idx on public.worksheet_attempts(assignment_id,started_at desc);
create table public.answers (
 id uuid primary key default gen_random_uuid(),
 attempt_id uuid not null references public.worksheet_attempts(id),
 question_id text not null,
 answer_type text not null check(answer_type in ('multiple-choice','typed','paper','unanswered')),
 value_json jsonb not null check(jsonb_typeof(value_json)='object'),
 revision integer not null default 1 check(revision>0),
 updated_at timestamptz not null default now(),
 unique(attempt_id,question_id)
);
create table public.sync_operations (
 id uuid primary key,
 attempt_id uuid not null references public.worksheet_attempts(id),
 operation_type text not null check(operation_type in ('start_attempt','save_answer')),
 request_hash text not null check(request_hash ~ '^[0-9a-f]{64}$'),
 result_json jsonb not null,
 processed_at timestamptz not null default now()
);
alter table public.worksheet_attempts enable row level security;
alter table public.answers enable row level security;
alter table public.sync_operations enable row level security;
revoke all on public.worksheet_attempts,public.answers,public.sync_operations from public,anon,authenticated,service_role;
-- Only assignment metadata reads need this; answer reads/writes stay behind RPCs.
grant select on public.worksheet_attempts to service_role;

-- Internal payload builder: never expose this helper as an executable client RPC.
create function public.child_attempt_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select jsonb_build_object(
  'id',a.id,'assignmentId',a.assignment_id,'childId',a.child_id,'worksheetVersionId',a.worksheet_version_id,
  'status',a.status,'startedAt',a.started_at,'writable',a.status='in_progress' and assignment.status='active',
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

create function public.start_child_attempt(p_token_hash text,p_assignment_id uuid,p_request_id uuid,p_request_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_child_id uuid;v_assignment public.worksheet_assignments;
 v_attempt public.worksheet_attempts;v_operation public.sync_operations;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 v_child_id:=(v_session->'child'->>'id')::uuid;
 select * into v_assignment from public.worksheet_assignments where id=p_assignment_id and child_id=v_child_id for update;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 select * into v_operation from public.sync_operations where id=p_request_id;
 if found then
  if v_operation.operation_type<>'start_attempt' or v_operation.request_hash<>p_request_hash
    or not exists(select 1 from public.worksheet_attempts where id=v_operation.attempt_id and child_id=v_child_id and assignment_id=p_assignment_id) then
    return jsonb_build_object('error','OPERATION_REUSED');
  end if;
  return public.child_attempt_payload(v_operation.attempt_id);
 end if;
 if v_assignment.status<>'active' then return jsonb_build_object('error','ASSIGNMENT_WITHDRAWN');end if;
 select * into v_attempt from public.worksheet_attempts where assignment_id=p_assignment_id and status='in_progress';
 if not found then
  insert into public.worksheet_attempts(assignment_id,child_id,worksheet_version_id)
    values(p_assignment_id,v_child_id,v_assignment.worksheet_version_id) returning * into v_attempt;
 end if;
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_request_id,v_attempt.id,'start_attempt',p_request_hash,jsonb_build_object('attemptId',v_attempt.id));
 return public.child_attempt_payload(v_attempt.id);
end;
$$;

create function public.get_child_attempt(p_token_hash text,p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 if not exists(select 1 from public.worksheet_attempts where id=p_attempt_id and child_id=(v_session->'child'->>'id')::uuid) then
  return jsonb_build_object('error','ATTEMPT_NOT_FOUND');
 end if;
 return public.child_attempt_payload(p_attempt_id);
end;
$$;

create function public.save_child_answer(p_token_hash text,p_attempt_id uuid,p_question_id text,
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
 elsif v_mode='typed' then
  if v_question->>'type'<>'written' or jsonb_typeof(p_answer->'text') is distinct from 'string'
   or char_length(p_answer->>'text')>5000 or exists(select 1 from jsonb_object_keys(p_answer) k where k not in ('mode','text')) then
   return jsonb_build_object('error','INVALID_ANSWER');end if;
 elsif v_mode='paper' then
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
revoke all on function public.start_child_attempt(text,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.get_child_attempt(text,uuid) from public,anon,authenticated;
revoke all on function public.save_child_answer(text,uuid,text,uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function public.start_child_attempt(text,uuid,uuid,text) to service_role;
grant execute on function public.get_child_attempt(text,uuid) to service_role;
grant execute on function public.save_child_answer(text,uuid,text,uuid,text,integer,jsonb) to service_role;
notify pgrst,'reload schema';
commit;
