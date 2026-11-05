begin;
-- Number attempts within an assignment, preserving every existing attempt and answer.
alter table public.worksheet_attempts add column attempt_number integer;
with numbered as (
 select id,row_number() over(partition by assignment_id order by started_at,id)::integer as number
 from public.worksheet_attempts
) update public.worksheet_attempts a set attempt_number=n.number from numbered n where a.id=n.id;
alter table public.worksheet_attempts alter column attempt_number set not null;
alter table public.worksheet_attempts add constraint worksheet_attempts_number_positive check(attempt_number>0);
alter table public.worksheet_attempts add constraint worksheet_attempts_assignment_number_unique unique(assignment_id,attempt_number);

create or replace function public.child_attempt_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select jsonb_build_object(
  'id',a.id,'attemptNumber',a.attempt_number,'assignmentId',a.assignment_id,'childId',a.child_id,'worksheetVersionId',a.worksheet_version_id,
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

create or replace function public.attempt_submission_summary(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 with items as (
  select q.value->>'type' as question_type,q.value->>'correctAnswer' as expected_option,
    a.value_json->>'selectedOptionId' as selected_option,
    coalesce(case when q.value->>'type'='multiple-choice' then a.answer_type='multiple-choice'
      else a.answer_type='paper' or (a.answer_type='typed' and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g'))>0) end,false) as answered,
    r.id as review_id,r.classification
  from public.worksheet_attempts attempt join public.worksheet_versions v on v.id=attempt.worksheet_version_id
  cross join lateral jsonb_array_elements(v.content_json->'questions') q(value)
  left join public.answers a on a.attempt_id=attempt.id and a.question_id=q.value->>'id'
  left join public.answer_reviews r on r.answer_id=a.id where attempt.id=p_attempt_id
 ), totals as (
  select count(*)::integer as total,
   count(*) filter(where question_type='multiple-choice')::integer as choice_total,
   count(*) filter(where question_type='multiple-choice' and answered and selected_option=expected_option)::integer as choice_correct,
   count(*) filter(where question_type='multiple-choice' and not answered)::integer as choice_unanswered,
   count(*) filter(where question_type='written')::integer as written_total,
   count(*) filter(where question_type='written' and answered)::integer as written_answered,
   count(*) filter(where question_type='written' and answered and review_id is null)::integer as pending_review,
   count(*) filter(where question_type='written' and classification='correct')::integer as written_correct,
   count(*) filter(where question_type='written' and classification='partially_correct')::integer as written_partial,
   count(*) filter(where question_type='written' and classification='incorrect')::integer as written_incorrect,
   count(*) filter(where not answered)::integer as unanswered from items
 ) select jsonb_build_object('attemptId',a.id,'attemptNumber',a.attempt_number,'assignmentId',a.assignment_id,'childId',a.child_id,
  'status',a.status,'submittedAt',a.submitted_at,'title',w.title,'subjectName',s.name,
  'questionCount',t.total,'choiceTotal',t.choice_total,'choiceCorrect',t.choice_correct,
  'choiceUnanswered',t.choice_unanswered,'writtenTotal',t.written_total,'writtenAnswered',t.written_answered,
  'writtenCorrect',t.written_correct,'writtenPartial',t.written_partial,'writtenIncorrect',t.written_incorrect,
  'pendingReview',t.pending_review,'unansweredTotal',t.unanswered)
 from public.worksheet_attempts a join public.worksheet_versions v on v.id=a.worksheet_version_id
 join public.worksheets w on w.id=v.worksheet_id join public.subjects s on s.id=w.subject_id cross join totals t
 where a.id=p_attempt_id;
$$;
revoke all on function public.attempt_submission_summary(uuid) from public,anon,authenticated,service_role;


create or replace function public.list_parent_child_attempts(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,
 p_child_id uuid,p_cursor uuid default null,p_subject_id uuid default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb;v_cursor public.worksheet_attempts;v_items jsonb;v_next uuid;
begin
 v_access:=public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
 if v_access ? 'error' then return v_access;end if;
 perform 1 from public.children c join public.families f on f.id=c.family_id join public.family_members m on m.family_id=f.id
 where c.id=p_child_id and f.status='active' and m.adult_user_id=p_actor_id and m.status='active';
 if not found then return jsonb_build_object('error','CHILD_NOT_FOUND');end if;
 if p_status is not null and p_status not in ('in_progress','submitted','pending_review','completed','abandoned') then
  return jsonb_build_object('error','INVALID_REQUEST');end if;
 if p_cursor is not null then
  select * into v_cursor from public.worksheet_attempts where id=p_cursor and child_id=p_child_id;
  if not found then return jsonb_build_object('error','INVALID_REQUEST');end if;
 end if;
 with page as (
  select a.*,w.title,w.subject_id,s.name as subject_name,wa.status='active' as assignment_active,
   jsonb_array_length(v.content_json->'questions') as question_count
  from public.worksheet_attempts a join public.worksheet_assignments wa on wa.id=a.assignment_id
  join public.worksheet_versions v on v.id=a.worksheet_version_id join public.worksheets w on w.id=v.worksheet_id
  join public.subjects s on s.id=w.subject_id
  where a.child_id=p_child_id and (p_subject_id is null or w.subject_id=p_subject_id)
   and (p_status is null or a.status=p_status)
   and (p_cursor is null or (a.started_at,a.id)<(v_cursor.started_at,v_cursor.id))
  order by a.started_at desc,a.id desc limit 51
 ), numbered as (select page.*,row_number() over(order by started_at desc,id desc) as page_number from page)
 select coalesce(jsonb_agg(jsonb_build_object('attemptId',id,'attemptNumber',attempt_number,'childId',child_id,'title',title,
  'subjectId',subject_id,'subjectName',subject_name,'status',status,'startedAt',started_at,'submittedAt',submitted_at,
  'assignmentActive',assignment_active,'questionCount',question_count,
  'summary',case when status in ('submitted','pending_review','completed') then public.attempt_submission_summary(id) else null end)
  order by started_at desc,id desc) filter(where page_number<=50),'[]'::jsonb),
  case when count(*)>50 then (array_agg(id order by started_at desc,id desc))[50] else null end
 into v_items,v_next from numbered;
 return jsonb_build_object('items',v_items,'nextCursor',v_next);
end;
$$;

-- Replace the old signature rather than leaving ambiguous default-argument overloads.
-- Calls from the previous deployment still work through the optional final parameter.
drop function public.start_child_attempt(text,uuid,uuid,text);
create function public.start_child_attempt(p_token_hash text,p_assignment_id uuid,p_request_id uuid,p_request_hash text,
 p_previous_attempt_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_child_id uuid;v_assignment public.worksheet_assignments;
 v_attempt public.worksheet_attempts;v_previous public.worksheet_attempts;v_latest public.worksheet_attempts;
 v_operation public.sync_operations;v_created boolean:=false;v_family_id uuid;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 v_child_id:=(v_session->'child'->>'id')::uuid;
 if p_request_id is null or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('error','INVALID_REQUEST');end if;
 -- Serializes first starts and repetitions; answer saves/submission already lock this assignment.
 select * into v_assignment from public.worksheet_assignments where id=p_assignment_id and child_id=v_child_id for update;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 select * into v_operation from public.sync_operations where id=p_request_id;
 if found then
  if v_operation.operation_type<>'start_attempt' or v_operation.request_hash<>p_request_hash
    or not exists(select 1 from public.worksheet_attempts where id=v_operation.attempt_id and child_id=v_child_id and assignment_id=p_assignment_id) then
   return jsonb_build_object('error','OPERATION_REUSED');end if;
  return public.child_attempt_payload(v_operation.attempt_id);
 end if;
 if v_assignment.status<>'active' then return jsonb_build_object('error','ASSIGNMENT_WITHDRAWN');end if;
 select * into v_latest from public.worksheet_attempts where assignment_id=p_assignment_id order by attempt_number desc limit 1;
 select * into v_attempt from public.worksheet_attempts where assignment_id=p_assignment_id and status='in_progress';
 if p_previous_attempt_id is not null then
  select * into v_previous from public.worksheet_attempts where id=p_previous_attempt_id and assignment_id=p_assignment_id and child_id=v_child_id;
  if not found or v_previous.status<>'completed' then return jsonb_build_object('error','REPEAT_NOT_AVAILABLE');end if;
  -- A second device joins the current attempt instead of creating a parallel one.
  if v_attempt.id is null and v_latest.id is distinct from p_previous_attempt_id then
   return jsonb_build_object('error','REPEAT_STATE_CHANGED');end if;
 elsif v_attempt.id is null and v_latest.id is not null then
  -- An outdated first-start screen must never create an unintended repetition.
  v_attempt:=v_latest;
 end if;
 if v_attempt.id is null then
  insert into public.worksheet_attempts(assignment_id,child_id,worksheet_version_id,attempt_number,started_at)
   values(p_assignment_id,v_child_id,v_assignment.worksheet_version_id,coalesce(v_latest.attempt_number,0)+1,clock_timestamp())
   returning * into v_attempt;
  v_created:=true;
 end if;
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_request_id,v_attempt.id,'start_attempt',p_request_hash,jsonb_build_object('attemptId',v_attempt.id));
 if v_created then
  select family_id into v_family_id from public.children where id=v_child_id;
  insert into public.family_audit_events(family_id,event_type,payload)
   values(v_family_id,case when p_previous_attempt_id is null then 'attempt.started' else 'attempt.repeated' end,
    jsonb_build_object('actorType','child','childId',v_child_id,'assignmentId',p_assignment_id,'attemptId',v_attempt.id,
     'attemptNumber',v_attempt.attempt_number,'previousAttemptId',p_previous_attempt_id));
 end if;
 -- No answer/review copying: a newly inserted attempt has its own empty answer set.
 return public.child_attempt_payload(v_attempt.id);
end;
$$;
revoke all on function public.start_child_attempt(text,uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.start_child_attempt(text,uuid,uuid,text,uuid) to service_role;

-- One metadata row per assignment avoids truncating the child list after many repetitions.
create view public.assignment_attempt_state with(security_invoker=true) as
 select wa.id as assignment_id,wa.child_id,active.id as active_attempt_id,
  latest.id as latest_attempt_id,latest.status as latest_attempt_status,latest.attempt_number as latest_attempt_number
 from public.worksheet_assignments wa
 left join lateral(select id from public.worksheet_attempts a where a.assignment_id=wa.id and a.status='in_progress' limit 1) active on true
 left join lateral(select id,status,attempt_number from public.worksheet_attempts a where a.assignment_id=wa.id
  and a.status in ('in_progress','submitted','pending_review','completed') order by attempt_number desc limit 1) latest on true;
revoke all on public.assignment_attempt_state from public,anon,authenticated,service_role;
grant select on public.assignment_attempt_state to service_role;
revoke all on function public.list_parent_child_attempts(uuid,uuid,text,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.list_parent_child_attempts(uuid,uuid,text,uuid,uuid,uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
