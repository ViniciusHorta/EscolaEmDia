begin;
create index worksheet_attempts_child_started_idx on public.worksheet_attempts(child_id,started_at desc,id desc);

create function public.get_parent_child_progress(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,p_child_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access jsonb;v_child public.children;v_subjects jsonb;v_overview jsonb;
begin
 v_access:=public.use_parent_unlock(p_actor_id,p_auth_session_id,p_unlock_hash,true,false);
 if v_access ? 'error' then return v_access;end if;
 select c.* into v_child from public.children c join public.families f on f.id=c.family_id
 join public.family_members m on m.family_id=f.id
 where c.id=p_child_id and f.status='active' and m.adult_user_id=p_actor_id and m.status='active';
 if not found then return jsonb_build_object('error','CHILD_NOT_FOUND');end if;
 -- Results cover delivered attempts only, including historical/withdrawn assignments.
 with allocations as (
  select w.subject_id,count(*)::integer as assigned_total,
   count(*) filter(where not exists(select 1 from public.worksheet_attempts a where a.assignment_id=wa.id
    and a.status in ('in_progress','submitted','pending_review','completed')))::integer as to_start
  from public.worksheet_assignments wa join public.worksheet_versions v on v.id=wa.worksheet_version_id
  join public.worksheets w on w.id=v.worksheet_id where wa.child_id=p_child_id and wa.status='active' group by w.subject_id
 ), runs as materialized (
  select w.subject_id,a.status,
   case when a.status in ('submitted','pending_review','completed') then public.attempt_submission_summary(a.id) else null end as result
  from public.worksheet_attempts a join public.worksheet_versions v on v.id=a.worksheet_version_id
  join public.worksheets w on w.id=v.worksheet_id where a.child_id=p_child_id
 ), results as (
  select subject_id,count(*) filter(where status='in_progress')::integer as in_progress,
   count(*) filter(where status in ('submitted','pending_review','completed'))::integer as delivered,
   count(*) filter(where status='completed')::integer as completed,
   count(*) filter(where status in ('submitted','pending_review') and (result->>'pendingReview')::integer>0)::integer as pending_attempts,
   coalesce(sum((result->>'pendingReview')::integer),0)::integer as pending_answers,
   coalesce(sum((result->>'choiceTotal')::integer),0)::integer as choice_total,
   coalesce(sum((result->>'choiceCorrect')::integer),0)::integer as choice_correct,
   coalesce(sum((result->>'writtenAnswered')::integer),0)::integer as written_answered,
   coalesce(sum((result->>'writtenCorrect')::integer),0)::integer as written_correct,
   coalesce(sum((result->>'writtenPartial')::integer),0)::integer as written_partial,
   coalesce(sum((result->>'writtenIncorrect')::integer),0)::integer as written_incorrect,
   coalesce(sum((result->>'unansweredTotal')::integer),0)::integer as unanswered
  from runs group by subject_id
 ), subject_rows as (
  select s.id,s.name,coalesce(a.assigned_total,0) as assigned_total,coalesce(a.to_start,0) as to_start,
   coalesce(r.in_progress,0) as in_progress,coalesce(r.delivered,0) as delivered,coalesce(r.completed,0) as completed,
   coalesce(r.pending_attempts,0) as pending_attempts,coalesce(r.pending_answers,0) as pending_answers,
   coalesce(r.choice_total,0) as choice_total,coalesce(r.choice_correct,0) as choice_correct,
   coalesce(r.written_answered,0) as written_answered,coalesce(r.written_correct,0) as written_correct,
   coalesce(r.written_partial,0) as written_partial,coalesce(r.written_incorrect,0) as written_incorrect,
   coalesce(r.unanswered,0) as unanswered
  from public.subjects s left join allocations a on a.subject_id=s.id left join results r on r.subject_id=s.id
  where a.subject_id is not null or r.subject_id is not null
 )
 select coalesce(jsonb_agg(jsonb_build_object('subjectId',id,'subjectName',name,
  'assignedTotal',assigned_total,'toStart',to_start,'inProgress',in_progress,'delivered',delivered,'completed',completed,
  'pendingAttempts',pending_attempts,'pendingAnswers',pending_answers,'choiceTotal',choice_total,'choiceCorrect',choice_correct,
  'writtenAnswered',written_answered,'writtenCorrect',written_correct,'writtenPartial',written_partial,
  'writtenIncorrect',written_incorrect,'unansweredTotal',unanswered) order by name,id),'[]'::jsonb),
  jsonb_build_object('assignedTotal',coalesce(sum(assigned_total),0),'toStart',coalesce(sum(to_start),0),
   'inProgress',coalesce(sum(in_progress),0),'delivered',coalesce(sum(delivered),0),'completed',coalesce(sum(completed),0),
   'pendingAttempts',coalesce(sum(pending_attempts),0),'pendingAnswers',coalesce(sum(pending_answers),0))
 into v_subjects,v_overview from subject_rows;
 return jsonb_build_object('child',jsonb_build_object('id',v_child.id,'familyId',v_child.family_id,
  'displayName',v_child.display_name,'schoolYear',v_child.school_year,'avatarId',v_child.avatar_id),
  'overview',v_overview,'subjects',v_subjects);
end;
$$;

create function public.list_parent_child_attempts(p_actor_id uuid,p_auth_session_id uuid,p_unlock_hash text,
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
 select coalesce(jsonb_agg(jsonb_build_object('attemptId',id,'childId',child_id,'title',title,
  'subjectId',subject_id,'subjectName',subject_name,'status',status,'startedAt',started_at,'submittedAt',submitted_at,
  'assignmentActive',assignment_active,'questionCount',question_count,
  'summary',case when status in ('submitted','pending_review','completed') then public.attempt_submission_summary(id) else null end)
  order by started_at desc,id desc) filter(where page_number<=50),'[]'::jsonb),
  case when count(*)>50 then (array_agg(id order by started_at desc,id desc))[50] else null end
 into v_items,v_next from numbered;
 return jsonb_build_object('items',v_items,'nextCursor',v_next);
end;
$$;
revoke all on function public.get_parent_child_progress(uuid,uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.list_parent_child_attempts(uuid,uuid,text,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.get_parent_child_progress(uuid,uuid,text,uuid) to service_role;
grant execute on function public.list_parent_child_attempts(uuid,uuid,text,uuid,uuid,uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
