begin;
-- Imagem opcional nas questões.
-- Conteúdo: qualquer tipo de questão pode ter "image":{"path":"<ficheiro no bucket question-images>","alt":"…"}.
--   path: caminho relativo no bucket (ex.: "a1b2c3.png"); só letras, números, / _ . - e extensão de imagem.
--   alt:  texto alternativo (opcional, até 300 caracteres) — lido por leitores de ecrã.
-- O app monta o URL público: <SUPABASE_URL>/storage/v1/object/public/question-images/<path>.
-- Guarda-se o caminho (não o URL) para o conteúdo não depender do ambiente.
-- Questões sem "image" continuam exatamente iguais.

create or replace function public.valid_question_image(p_image jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_image) = 'object'
    and jsonb_typeof(p_image->'path') = 'string'
    and char_length(p_image->>'path') between 5 and 200
    and (p_image->>'path') ~ '^[A-Za-z0-9_-][A-Za-z0-9/_.-]*\.(png|jpe?g|webp|gif)$'
    and position('..' in p_image->>'path') = 0
    and position('//' in p_image->>'path') = 0
    and (not p_image ? 'alt' or (jsonb_typeof(p_image->'alt') = 'string' and char_length(p_image->>'alt') <= 300))
    and (select count(*) from jsonb_object_keys(p_image) k where k not in ('path', 'alt')) = 0;
$$;
revoke all on function public.valid_question_image(jsonb) from public,anon,authenticated;

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
    if q ? 'image' and not public.valid_question_image(q->'image') then return false; end if;
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
      if jsonb_typeof(q->'correctAnswer') is distinct from 'boolean' or q ? 'options' then return false; end if;
    end if;
  end loop;
  return true;
end;
$$;

-- Ficha da criança: acrescenta "image" quando existe.
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
      case when q.value ? 'image' then jsonb_build_object('image',q.value->'image') else '{}'::jsonb end ||
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

-- Revisão do responsável: acrescenta "image" (null quando não existe).
create or replace function public.parent_review_payload(p_attempt_id uuid)
returns jsonb language sql stable set search_path = '' as $$
 select public.attempt_submission_summary(a.id)||jsonb_build_object(
  'child',jsonb_build_object('id',c.id,'familyId',c.family_id,'displayName',c.display_name,'schoolYear',c.school_year,'avatarId',c.avatar_id),
  'instructions',coalesce(v.content_json->>'instructions',''),
  'text',coalesce(v.content_json->>'text',''),'audioText',coalesce(v.content_json->>'audioText',''),
  'questions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',q.value->>'id','type',q.value->>'type','prompt',q.value->>'prompt',
    'image',q.value->'image',
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

-- Correção vista pela criança: acrescenta "image" (null quando não existe).
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
  'image',q.value->'image',
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
