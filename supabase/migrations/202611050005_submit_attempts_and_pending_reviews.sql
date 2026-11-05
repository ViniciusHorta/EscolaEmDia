begin;
alter table public.sync_operations drop constraint sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
 check(operation_type in ('start_attempt','save_answer','submit_attempt'));
alter table public.worksheet_attempts add constraint worksheet_attempts_submitted_timestamp_check
 check(status not in ('submitted','pending_review','completed') or submitted_at is not null);
create table public.answer_reviews (
 id uuid primary key default gen_random_uuid(),
 answer_id uuid not null unique references public.answers(id),
 classification text not null check(classification in ('correct','partially_correct','incorrect')),
 reviewed_by uuid not null references auth.users(id),reviewed_at timestamptz not null default now(),
 revision integer not null default 1 check(revision>0)
);
create table public.answer_review_events (
 id uuid primary key default gen_random_uuid(),answer_review_id uuid not null references public.answer_reviews(id),
 previous_classification text check(previous_classification in ('correct','partially_correct','incorrect')),
 new_classification text not null check(new_classification in ('correct','partially_correct','incorrect')),
 changed_by uuid not null references auth.users(id),changed_at timestamptz not null default now()
);
alter table public.answer_reviews enable row level security;
alter table public.answer_review_events enable row level security;
revoke all on public.answer_reviews,public.answer_review_events from public,anon,authenticated,service_role;

-- Derived result only: no global grade is stored and no solution is returned.
create function public.attempt_submission_summary(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 with items as (
  select q.value->>'type' as question_type,q.value->>'correctAnswer' as expected_option,
    a.value_json->>'selectedOptionId' as selected_option,
    coalesce(case when q.value->>'type'='multiple-choice' then a.answer_type='multiple-choice'
      else a.answer_type='paper' or (a.answer_type='typed' and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g'))>0) end,false) as answered,
    r.id as review_id
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
   count(*) filter(where not answered)::integer as unanswered from items
 ) select jsonb_build_object('attemptId',a.id,'assignmentId',a.assignment_id,'childId',a.child_id,
  'status',a.status,'submittedAt',a.submitted_at,'title',w.title,'subjectName',s.name,
  'questionCount',t.total,'choiceTotal',t.choice_total,'choiceCorrect',t.choice_correct,
  'choiceUnanswered',t.choice_unanswered,'writtenTotal',t.written_total,'writtenAnswered',t.written_answered,
  'pendingReview',t.pending_review,'unansweredTotal',t.unanswered)
 from public.worksheet_attempts a join public.worksheet_versions v on v.id=a.worksheet_version_id
 join public.worksheets w on w.id=v.worksheet_id join public.subjects s on s.id=w.subject_id cross join totals t
 where a.id=p_attempt_id;
$$;
revoke all on function public.attempt_submission_summary(uuid) from public,anon,authenticated,service_role;

create function public.submit_child_attempt(p_token_hash text,p_attempt_id uuid,p_operation_id uuid,
 p_request_hash text,p_expected_revisions jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_attempt public.worksheet_attempts;v_assignment public.worksheet_assignments;
 v_operation public.sync_operations;v_question jsonb;v_revision integer;v_summary jsonb;v_family_id uuid;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 select assignment.* into v_assignment from public.worksheet_assignments assignment
  join public.worksheet_attempts attempt on attempt.assignment_id=assignment.id
  where attempt.id=p_attempt_id and attempt.child_id=(v_session->'child'->>'id')::uuid for share of assignment;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 select * into v_attempt from public.worksheet_attempts where id=p_attempt_id for update;
 select * into v_operation from public.sync_operations where id=p_operation_id;
 if found then
  if v_operation.attempt_id<>p_attempt_id or v_operation.operation_type<>'submit_attempt' or v_operation.request_hash<>p_request_hash then
   return jsonb_build_object('error','OPERATION_REUSED');end if;
  return public.attempt_submission_summary(p_attempt_id);
 end if;
 if v_attempt.status<>'in_progress' then return jsonb_build_object('error','ATTEMPT_READ_ONLY');end if;
 if v_assignment.status<>'active' then return jsonb_build_object('error','ASSIGNMENT_WITHDRAWN');end if;
 if jsonb_typeof(p_expected_revisions) is distinct from 'object' then return jsonb_build_object('error','INVALID_REQUEST');end if;
 if (select count(*) from jsonb_object_keys(p_expected_revisions))<>(select jsonb_array_length(content_json->'questions') from public.worksheet_versions where id=v_attempt.worksheet_version_id) then
  return jsonb_build_object('error','INVALID_REQUEST');end if;
 for v_question in select q.value from public.worksheet_versions v,
   lateral jsonb_array_elements(v.content_json->'questions') q(value) where v.id=v_attempt.worksheet_version_id loop
  if not (p_expected_revisions ? (v_question->>'id'))
    or jsonb_typeof(p_expected_revisions->(v_question->>'id')) is distinct from 'number'
    or (p_expected_revisions->>(v_question->>'id')) !~ '^[0-9]{1,10}$' then
   return jsonb_build_object('error','INVALID_REQUEST');end if;
  select revision into v_revision from public.answers where attempt_id=p_attempt_id and question_id=v_question->>'id';
  if coalesce(v_revision,0)::bigint<>(p_expected_revisions->>(v_question->>'id'))::bigint then
   return jsonb_build_object('error','ATTEMPT_REVISION_CONFLICT');end if;
 end loop;
 v_summary:=public.attempt_submission_summary(p_attempt_id);
 update public.worksheet_attempts set submitted_at=now(),
   status=case when (v_summary->>'pendingReview')::integer>0 then 'pending_review' else 'completed' end
   where id=p_attempt_id;
 select family_id into v_family_id from public.children where id=v_attempt.child_id;
 insert into public.family_audit_events(family_id,event_type,payload)
  values(v_family_id,'attempt.submitted',jsonb_build_object('actorType','child','childId',v_attempt.child_id,'attemptId',p_attempt_id));
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_operation_id,p_attempt_id,'submit_attempt',p_request_hash,jsonb_build_object('attemptId',p_attempt_id));
 return public.attempt_submission_summary(p_attempt_id);
end;
$$;

create function public.get_child_attempt_result(p_token_hash text,p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_status text;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 select status into v_status from public.worksheet_attempts where id=p_attempt_id and child_id=(v_session->'child'->>'id')::uuid;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 if v_status not in ('submitted','pending_review','completed') then return jsonb_build_object('error','ATTEMPT_NOT_SUBMITTED');end if;
 return public.attempt_submission_summary(p_attempt_id);
end;
$$;

create function public.list_parent_pending_reviews(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_family_id uuid,p_cursor uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb;v_cursor public.worksheet_attempts;v_items jsonb;v_next uuid;
begin
 v_access:=public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
 if v_access ? 'error' then return v_access;end if;
 perform 1 from public.families f join public.family_members m on m.family_id=f.id
  where f.id=p_family_id and f.status='active' and m.adult_user_id=p_actor_id and m.status='active';
 if not found then return jsonb_build_object('error','FAMILY_NOT_FOUND');end if;
 if p_cursor is not null then
  select a.* into v_cursor from public.worksheet_attempts a join public.children c on c.id=a.child_id where a.id=p_cursor and c.family_id=p_family_id;
  if not found or v_cursor.submitted_at is null then return jsonb_build_object('error','INVALID_REQUEST');end if;
 end if;
 with page as (
  select a.*,c.display_name,c.school_year,c.avatar_id from public.worksheet_attempts a
  join public.children c on c.id=a.child_id where c.family_id=p_family_id and a.status='pending_review'
    and (p_cursor is null or (a.child_id,a.submitted_at,a.id)>(v_cursor.child_id,v_cursor.submitted_at,v_cursor.id))
  order by a.child_id,a.submitted_at,a.id limit 51
 ), numbered as (select page.*,row_number() over(order by child_id,submitted_at,id) as page_number from page)
 select coalesce(jsonb_agg(public.attempt_submission_summary(id)||jsonb_build_object('child',jsonb_build_object(
  'id',child_id,'familyId',p_family_id,'displayName',display_name,'schoolYear',school_year,'avatarId',avatar_id)) order by child_id,submitted_at,id) filter(where page_number<=50),'[]'::jsonb),
  case when count(*)>50 then (array_agg(id order by child_id,submitted_at,id))[50] else null end
 into v_items,v_next from numbered;
 return jsonb_build_object('items',v_items,'nextCursor',v_next);
end;
$$;
revoke all on function public.submit_child_attempt(text,uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.get_child_attempt_result(text,uuid) from public,anon,authenticated;
revoke all on function public.list_parent_pending_reviews(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.submit_child_attempt(text,uuid,uuid,text,jsonb) to service_role;
grant execute on function public.get_child_attempt_result(text,uuid) to service_role;
grant execute on function public.list_parent_pending_reviews(uuid,uuid,text,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
