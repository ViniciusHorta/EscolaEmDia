begin;
-- Novo tipo de pergunta «Verdadeiro ou Falso» (true_false).
-- Conteúdo: {"type":"true_false","prompt":"…","correctAnswer":true|false,"explanation":"…"}
-- Resposta: {"mode":"true_false","value":true|false}. Sem seleção = pergunta não respondida.
-- Corrige-se automaticamente, como a escolha múltipla (conta em choiceTotal/choiceCorrect).
-- Os tipos existentes mantêm exatamente o mesmo comportamento.

alter table public.answers drop constraint answers_answer_type_check;
alter table public.answers add constraint answers_answer_type_check
  check(answer_type in ('multiple-choice','typed','paper','unanswered','true_false'));

create or replace function public.valid_worksheet_content(p_content jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare q jsonb; o jsonb; ids text[] := '{}'; option_ids text[];
begin
  if jsonb_typeof(p_content) is distinct from 'object'
    or jsonb_typeof(p_content->'questions') is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_content->'questions') not between 1 and 50 then return false; end if;
  for q in select value from jsonb_array_elements(p_content->'questions') loop
    if jsonb_typeof(q) is distinct from 'object' or jsonb_typeof(q->'id') is distinct from 'string'
      or coalesce(btrim(q->>'id'),'')='' or (q->>'id')=any(ids)
      or jsonb_typeof(q->'prompt') is distinct from 'string' or coalesce(btrim(q->>'prompt'),'')=''
      or coalesce(q->>'type','') not in ('multiple-choice','written','true_false') then return false; end if;
    ids := array_append(ids,q->>'id');
    if q->>'type'='multiple-choice' then
      if jsonb_typeof(q->'options') is distinct from 'array' then return false; end if;
      if jsonb_array_length(q->'options') not between 2 and 8 then return false; end if;
      option_ids := '{}';
      for o in select value from jsonb_array_elements(q->'options') loop
        if jsonb_typeof(o) is distinct from 'object' or jsonb_typeof(o->'id') is distinct from 'string'
          or coalesce(btrim(o->>'id'),'')='' or (o->>'id')=any(option_ids)
          or jsonb_typeof(o->'text') is distinct from 'string' or coalesce(btrim(o->>'text'),'')='' then return false; end if;
        option_ids := array_append(option_ids,o->>'id');
      end loop;
      if jsonb_typeof(q->'correctAnswer') is distinct from 'string'
        or not coalesce((q->>'correctAnswer')=any(option_ids),false) then return false; end if;
    elsif q->>'type'='true_false' then
      -- Verdadeiro ou Falso: valor esperado booleano e sem opções próprias.
      if jsonb_typeof(q->'correctAnswer') is distinct from 'boolean' or q ? 'options' then return false; end if;
    end if;
  end loop;
  return true;
end;
$$;

create or replace view public.worksheet_catalogue with (security_invoker=true) as
select v.id as version_id,w.id as worksheet_id,w.title,w.status as worksheet_status,w.is_sample,
  w.subject_id,s.name as subject_name,v.school_year,v.version_number,v.published_at,
  jsonb_array_length(v.content_json->'questions') as question_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type' in ('multiple-choice','true_false')) as choice_count,
  (select count(*)::integer from jsonb_array_elements(v.content_json->'questions') q where q->>'type'='written') as written_count,
  array(select t.id from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_ids,
  array(select t.name from public.worksheet_version_topics vt join public.topics t on t.id=vt.topic_id
    where vt.worksheet_version_id=v.id order by t.id) as topic_names,
  not exists(select 1 from public.worksheet_versions newer where newer.worksheet_id=w.id
    and newer.published_at is not null and newer.version_number>v.version_number) as is_latest
from public.worksheet_versions v join public.worksheets w on w.id=v.worksheet_id
  join public.subjects s on s.id=w.subject_id where v.published_at is not null;

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

create or replace function public.attempt_submission_summary(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 with items as (
  select q.value->>'type' as question_type,q.value->>'correctAnswer' as expected_option,
    case when a.answer_type='true_false' then a.value_json->>'value' else a.value_json->>'selectedOptionId' end as selected_option,
    coalesce(case when q.value->>'type'='multiple-choice' then a.answer_type='multiple-choice'
      when q.value->>'type'='true_false' then a.answer_type='true_false'
      else a.answer_type='paper' or (a.answer_type='typed' and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g'))>0) end,false) as answered,
    r.id as review_id,r.classification
  from public.worksheet_attempts attempt join public.worksheet_versions v on v.id=attempt.worksheet_version_id
  cross join lateral jsonb_array_elements(v.content_json->'questions') q(value)
  left join public.answers a on a.attempt_id=attempt.id and a.question_id=q.value->>'id'
  left join public.answer_reviews r on r.answer_id=a.id where attempt.id=p_attempt_id
 ), totals as (
  select count(*)::integer as total,
   count(*) filter(where question_type in ('multiple-choice','true_false'))::integer as choice_total,
   count(*) filter(where question_type in ('multiple-choice','true_false') and answered and selected_option=expected_option)::integer as choice_correct,
   count(*) filter(where question_type in ('multiple-choice','true_false') and not answered)::integer as choice_unanswered,
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

create or replace function public.parent_review_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select public.attempt_submission_summary(a.id)||jsonb_build_object(
  'child',jsonb_build_object('id',c.id,'familyId',c.family_id,'displayName',c.display_name,'schoolYear',c.school_year,'avatarId',c.avatar_id),
  'instructions',coalesce(v.content_json->>'instructions',''),
  'text',coalesce(v.content_json->>'text',''),'audioText',coalesce(v.content_json->>'audioText',''),
  'questions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',q.value->>'id','type',q.value->>'type','prompt',q.value->>'prompt',
    'options',case when q.value->>'type'='multiple-choice' then (
      select jsonb_agg(jsonb_build_object('id',o.value->>'id','text',o.value->>'text') order by o.ordinality)
      from jsonb_array_elements(q.value->'options') with ordinality o(value,ordinality))
      when q.value->>'type'='true_false' then '[{"id":"true","text":"Verdadeiro"},{"id":"false","text":"Falso"}]'::jsonb
      else '[]'::jsonb end,
    'correctOptionId',case when q.value->>'type' in ('multiple-choice','true_false') then q.value->>'correctAnswer' else null end,
    'explanation',coalesce(q.value->>'explanation',''),
    'answerId',answer.id,'answerType',coalesce(answer.answer_type,'unanswered'),
    'text',case when answer.answer_type='typed' then answer.value_json->>'text' else null end,
    'selectedOptionId',case when answer.answer_type='multiple-choice' then answer.value_json->>'selectedOptionId'
      when answer.answer_type='true_false' then answer.value_json->>'value' else null end,
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

create or replace function public.get_child_attempt_feedback(p_token_hash text,p_attempt_id uuid)
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
   (select o.value->>'text' from jsonb_array_elements(q.value->'options') o(value) where o.value->>'id'=a.value_json->>'selectedOptionId')
   when q.value->>'type'='true_false' and a.answer_type='true_false' then
    case when (a.value_json->'value')::boolean then 'Verdadeiro' else 'Falso' end else null end,
  'correctOptionText',case when q.value->>'type'='multiple-choice' then
   (select o.value->>'text' from jsonb_array_elements(q.value->'options') o(value) where o.value->>'id'=q.value->>'correctAnswer')
   when q.value->>'type'='true_false' then
    case when (q.value->'correctAnswer')::boolean then 'Verdadeiro' else 'Falso' end else null end,
  'outcome',case when q.value->>'type'='multiple-choice' then
    case when a.answer_type is distinct from 'multiple-choice' then 'unanswered'
      when a.value_json->>'selectedOptionId'=q.value->>'correctAnswer' then 'correct' else 'incorrect' end
   when q.value->>'type'='true_false' then
    case when a.answer_type is distinct from 'true_false' then 'unanswered'
      when a.value_json->'value'=q.value->'correctAnswer' then 'correct' else 'incorrect' end
   when a.answer_type='paper' or (a.answer_type='typed' and length(regexp_replace(coalesce(a.value_json->>'text',''),'[[:space:]]','','g'))>0)
    then coalesce(r.classification,'pending_review') else 'unanswered' end,
  -- Only published explanations of automatic questions, never private grading rubrics or adult identity.
  'explanation',case when q.value->>'type' in ('multiple-choice','true_false') then coalesce(q.value->>'explanation','') else '' end
 ) order by q.ordinality),'[]'::jsonb) into v_questions
 from jsonb_array_elements(v_content->'questions') with ordinality q(value,ordinality)
 left join public.answers a on a.attempt_id=v_attempt.id and a.question_id=q.value->>'id'
 left join public.answer_reviews r on r.answer_id=a.id;
 return jsonb_build_object('summary',public.attempt_submission_summary(v_attempt.id),
  'instructions',coalesce(v_content->>'instructions',''),'text',coalesce(v_content->>'text',''),
  'audioText',coalesce(v_content->>'audioText',''),'questions',v_questions);
end;
$$;

notify pgrst, 'reload schema';
commit;
