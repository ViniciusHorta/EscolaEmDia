begin;
-- Only the owner of a completed attempt may consult its correction.
create function public.get_child_attempt_feedback(p_token_hash text,p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session jsonb;v_attempt public.worksheet_attempts;v_questions jsonb;v_content jsonb;
begin
 v_session:=public.use_child_session(p_token_hash,false);
 if v_session ? 'error' then return v_session;end if;
 select * into v_attempt from public.worksheet_attempts where id=p_attempt_id
  and child_id=(v_session->'child'->>'id')::uuid;
 if not found then return jsonb_build_object('error','ATTEMPT_NOT_FOUND');end if;
 if v_attempt.status<>'completed' then return jsonb_build_object('error','FEEDBACK_NOT_AVAILABLE');end if;
 select content_json into v_content from public.worksheet_versions where id=v_attempt.worksheet_version_id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.value->>'id','number',q.ordinality,'type',q.value->>'type','prompt',q.value->>'prompt',
  'answerType',coalesce(a.answer_type,'unanswered'),
  'answerText',case when a.answer_type='typed' then coalesce(a.value_json->>'text','') else '' end,
  'selectedOptionText',case when q.value->>'type'='multiple-choice' and a.answer_type='multiple-choice' then
   (select o.value->>'text' from jsonb_array_elements(q.value->'options') o(value) where o.value->>'id'=a.value_json->>'selectedOptionId') else null end,
  'correctOptionText',case when q.value->>'type'='multiple-choice' then
   (select o.value->>'text' from jsonb_array_elements(q.value->'options') o(value) where o.value->>'id'=q.value->>'correctAnswer') else null end,
  'outcome',case when q.value->>'type'='multiple-choice' then
    case when a.answer_type is distinct from 'multiple-choice' then 'unanswered'
      when a.value_json->>'selectedOptionId'=q.value->>'correctAnswer' then 'correct' else 'incorrect' end
   when a.answer_type='paper' or (a.answer_type='typed' and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g'))>0)
    then coalesce(r.classification,'pending_review') else 'unanswered' end,
  -- Only published multiple-choice explanations, never private grading rubrics or adult identity.
  'explanation',case when q.value->>'type'='multiple-choice' then coalesce(q.value->>'explanation','') else '' end
 ) order by q.ordinality),'[]'::jsonb) into v_questions
 from jsonb_array_elements(v_content->'questions') with ordinality q(value,ordinality)
 left join public.answers a on a.attempt_id=v_attempt.id and a.question_id=q.value->>'id'
 left join public.answer_reviews r on r.answer_id=a.id;
 return jsonb_build_object('summary',public.attempt_submission_summary(v_attempt.id),
  'instructions',coalesce(v_content->>'instructions',''),'text',coalesce(v_content->>'text',''),
  'audioText',coalesce(v_content->>'audioText',''),'questions',v_questions);
end;
$$;
revoke all on function public.get_child_attempt_feedback(text,uuid) from public,anon,authenticated;
grant execute on function public.get_child_attempt_feedback(text,uuid) to service_role;

-- Append completed-attempt metadata without changing the existing view columns.
create or replace view public.assignment_attempt_state with(security_invoker=true) as
 select wa.id as assignment_id,wa.child_id,active.id as active_attempt_id,
  latest.id as latest_attempt_id,latest.status as latest_attempt_status,latest.attempt_number as latest_attempt_number,
  completed.id as latest_completed_attempt_id,completed.attempt_number as latest_completed_attempt_number
 from public.worksheet_assignments wa
 left join lateral(select id from public.worksheet_attempts a where a.assignment_id=wa.id and a.status='in_progress' limit 1) active on true
 left join lateral(select id,status,attempt_number from public.worksheet_attempts a where a.assignment_id=wa.id
  and a.status in ('in_progress','submitted','pending_review','completed') order by attempt_number desc limit 1) latest on true
 left join lateral(select id,attempt_number from public.worksheet_attempts a where a.assignment_id=wa.id
  and a.status='completed' order by attempt_number desc limit 1) completed on true;
revoke all on public.assignment_attempt_state from public,anon,authenticated,service_role;
grant select on public.assignment_attempt_state to service_role;
notify pgrst,'reload schema';
commit;
