begin;
-- Retain operation results so network retries cannot duplicate review history.
alter table public.sync_operations drop constraint sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
 check(operation_type in ('start_attempt','save_answer','submit_attempt','review_answer'));

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
 ) select jsonb_build_object('attemptId',a.id,'assignmentId',a.assignment_id,'childId',a.child_id,
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


-- Internal adult payload, never executable through the public/client API.
create function public.parent_review_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select public.attempt_submission_summary(a.id)||jsonb_build_object(
  'child',jsonb_build_object('id',c.id,'familyId',c.family_id,'displayName',c.display_name,'schoolYear',c.school_year,'avatarId',c.avatar_id),
  'instructions',coalesce(v.content_json->>'instructions',''),
  'text',coalesce(v.content_json->>'text',''),'audioText',coalesce(v.content_json->>'audioText',''),
  'questions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',q.value->>'id','type',q.value->>'type','prompt',q.value->>'prompt',
    'options',case when q.value->>'type'='multiple-choice' then (
      select jsonb_agg(jsonb_build_object('id',o.value->>'id','text',o.value->>'text') order by o.ordinality)
      from jsonb_array_elements(q.value->'options') with ordinality o(value,ordinality)) else '[]'::jsonb end,
    'correctOptionId',case when q.value->>'type'='multiple-choice' then q.value->>'correctAnswer' else null end,
    'explanation',coalesce(q.value->>'explanation',''),
    'answerId',answer.id,'answerType',coalesce(answer.answer_type,'unanswered'),
    'text',case when answer.answer_type='typed' then answer.value_json->>'text' else null end,
    'selectedOptionId',case when answer.answer_type='multiple-choice' then answer.value_json->>'selectedOptionId' else null end,
    'reviewable',coalesce(q.value->>'type'='written' and (answer.answer_type='paper' or
      (answer.answer_type='typed' and length(regexp_replace(coalesce(answer.value_json->>'text',''),'[[:space:]]','','g'))>0)),false),
    'review',case when r.id is not null then jsonb_build_object('answerReviewId',r.id,
      'classification',r.classification,'revision',r.revision,'reviewedAt',r.reviewed_at) else null end
   ) order by q.ordinality)
   from jsonb_array_elements(v.content_json->'questions') with ordinality q(value,ordinality)
   left join public.answers answer on answer.attempt_id=a.id and answer.question_id=q.value->>'id'
   left join public.answer_reviews r on r.answer_id=answer.id),'[]'::jsonb))
 from public.worksheet_attempts a join public.children c on c.id=a.child_id
 join public.worksheet_versions v on v.id=a.worksheet_version_id where a.id=p_attempt_id;
$$;
revoke all on function public.parent_review_payload(uuid) from public,anon,authenticated,service_role;

create function public.get_parent_attempt_review(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb;v_status text;
begin
 v_access:=public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
 if v_access ? 'error' then return v_access;end if;
 select a.status into v_status from public.worksheet_attempts a join public.children c on c.id=a.child_id
 join public.families f on f.id=c.family_id join public.family_members m on m.family_id=f.id
 where a.id=p_attempt_id and f.status='active' and m.adult_user_id=p_actor_id and m.status='active';
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 if v_status not in ('submitted','pending_review','completed') then return jsonb_build_object('error','ATTEMPT_NOT_SUBMITTED');end if;
 return public.parent_review_payload(p_attempt_id);
end;
$$;

create function public.save_parent_answer_review(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,
 p_answer_id uuid,p_classification text,p_base_revision integer,p_operation_id uuid,p_request_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb;v_attempt public.worksheet_attempts;v_answer public.answers;v_review public.answer_reviews;
 v_operation public.sync_operations;v_family_id uuid;v_question jsonb;v_previous text;v_result jsonb;v_summary jsonb;
begin
 v_access:=public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
 if v_access ? 'error' then return v_access;end if;
 if p_classification is null or p_classification not in ('correct','partially_correct','incorrect')
   or p_base_revision is null or p_base_revision<0 or p_base_revision>=2147483647
   or p_operation_id is null or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64}$' then
  return jsonb_build_object('error','INVALID_REQUEST');end if;
 -- Every review of an attempt takes this lock first, so the final pending count is atomic.
 select a.* into v_attempt from public.worksheet_attempts a join public.answers answer on answer.attempt_id=a.id
 join public.children c on c.id=a.child_id join public.families f on f.id=c.family_id
 join public.family_members m on m.family_id=f.id
 where answer.id=p_answer_id and f.status='active' and m.adult_user_id=p_actor_id and m.status='active'
 for update of a;
 if not found then return jsonb_build_object('error','ANSWER_NOT_FOUND');end if;
 select * into v_operation from public.sync_operations where id=p_operation_id;
 if found then
  if v_operation.attempt_id<>v_attempt.id or v_operation.operation_type<>'review_answer'
    or v_operation.request_hash<>p_request_hash then return jsonb_build_object('error','OPERATION_REUSED');end if;
  return v_operation.result_json||jsonb_build_object('detail',public.parent_review_payload(v_attempt.id));
 end if;
 if v_attempt.status not in ('submitted','pending_review','completed') then
  return jsonb_build_object('error','ATTEMPT_NOT_SUBMITTED');end if;
 select * into v_answer from public.answers where id=p_answer_id;
 select q.value into v_question from public.worksheet_versions v,
  lateral jsonb_array_elements(v.content_json->'questions') q(value)
  where v.id=v_attempt.worksheet_version_id and q.value->>'id'=v_answer.question_id;
 if v_question->>'type' is distinct from 'written' or not (
   v_answer.answer_type='paper' or (v_answer.answer_type='typed' and
     length(regexp_replace(coalesce(v_answer.value_json->>'text',''),'[[:space:]]','','g'))>0)) then
  return jsonb_build_object('error','ANSWER_NOT_REVIEWABLE');end if;
 select * into v_review from public.answer_reviews where answer_id=p_answer_id for update;
 if coalesce(v_review.revision,0)<>p_base_revision then return jsonb_build_object('error','REVIEW_REVISION_CONFLICT');end if;
 v_previous:=v_review.classification;
 if v_review.id is null then
  insert into public.answer_reviews(answer_id,classification,reviewed_by)
   values(p_answer_id,p_classification,p_actor_id) returning * into v_review;
 else
  update public.answer_reviews set classification=p_classification,reviewed_by=p_actor_id,reviewed_at=now(),revision=revision+1
   where id=v_review.id returning * into v_review;
 end if;
 insert into public.answer_review_events(answer_review_id,previous_classification,new_classification,changed_by)
  values(v_review.id,v_previous,p_classification,p_actor_id);
 v_summary:=public.attempt_submission_summary(v_attempt.id);
 update public.worksheet_attempts set status=case when (v_summary->>'pendingReview')::integer=0 then 'completed' else 'pending_review' end
  where id=v_attempt.id;
 select family_id into v_family_id from public.children where id=v_attempt.child_id;
 insert into public.family_audit_events(family_id,actor_id,event_type,payload)
  values(v_family_id,p_actor_id,'answer.reviewed',jsonb_build_object('attemptId',v_attempt.id,'answerId',p_answer_id,
   'answerReviewId',v_review.id,'previousClassification',v_previous,'classification',p_classification,'revision',v_review.revision));
 v_result:=jsonb_build_object('answerReviewId',v_review.id,'classification',v_review.classification,
  'revision',v_review.revision,'reviewedAt',v_review.reviewed_at,
  'attemptStatus',case when (v_summary->>'pendingReview')::integer=0 then 'completed' else 'pending_review' end,
  'summary',public.attempt_submission_summary(v_attempt.id));
 insert into public.sync_operations(id,attempt_id,operation_type,request_hash,result_json)
  values(p_operation_id,v_attempt.id,'review_answer',p_request_hash,v_result);
 return v_result||jsonb_build_object('detail',public.parent_review_payload(v_attempt.id));
end;
$$;

create function public.list_parent_completed_reviews(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_family_id uuid,p_cursor uuid default null)
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
  join public.children c on c.id=a.child_id where c.family_id=p_family_id and a.status='completed' and exists(select 1 from public.answers answer join public.answer_reviews review on review.answer_id=answer.id where answer.attempt_id=a.id)
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

revoke all on function public.get_parent_attempt_review(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.save_parent_answer_review(uuid,uuid,text,uuid,text,integer,uuid,text) from public,anon,authenticated;
revoke all on function public.list_parent_completed_reviews(uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_parent_attempt_review(uuid,uuid,text,uuid) to service_role;
grant execute on function public.save_parent_answer_review(uuid,uuid,text,uuid,text,integer,uuid,text) to service_role;
grant execute on function public.list_parent_completed_reviews(uuid,uuid,text,uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
