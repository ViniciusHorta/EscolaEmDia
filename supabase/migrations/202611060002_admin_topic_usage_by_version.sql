begin;

-- Separa o uso de cada tema entre a versão atual das fichas e versões antigas.
-- Antes, «worksheetCount» contava fichas cujo tema aparecia em QUALQUER versão; depois de retirar o tema
-- de uma ficha (nova versão), a ficha continuava a contar e não aparecia no filtro da lista de fichas.
--   • worksheetCount    — fichas cuja versão mais recente (publicada ou rascunho) usa o tema;
--   • historyWorksheets — fichas que só o usam em versões anteriores (imutáveis), com:
--       versionNumbers: versões que ainda usam o tema;
--       live: true se a versão publicada que os pais veem ainda o usa (a mais recente é um rascunho por publicar);
--       assigned: true se alguma dessas versões está atribuída a crianças.
--   • inUse             — o tema está ligado a alguma versão (não pode ser apagado).
create or replace function public.admin_catalogue_overview()
returns jsonb language sql stable security definer set search_path = '' as $$
  with latest as (
    select distinct on (v.worksheet_id) v.worksheet_id, v.id as version_id
    from public.worksheet_versions v order by v.worksheet_id, v.version_number desc
  ), latest_published as (
    select distinct on (v.worksheet_id) v.worksheet_id, v.id as version_id
    from public.worksheet_versions v where v.published_at is not null order by v.worksheet_id, v.version_number desc
  ), usage as (
    select vt.topic_id, v.worksheet_id, v.id as version_id, v.version_number,
      exists(select 1 from latest l where l.version_id = v.id) as is_latest,
      exists(select 1 from latest_published lp where lp.version_id = v.id) as is_live,
      exists(select 1 from public.worksheet_assignments a where a.worksheet_version_id = v.id) as is_assigned
    from public.worksheet_version_topics vt join public.worksheet_versions v on v.id = vt.worksheet_version_id
  )
  select jsonb_build_object(
    'subjects', coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name,
        'topicCount', (select count(*) from public.topics t where t.subject_id = s.id),
        'worksheetCount', (select count(*) from public.worksheets w where w.subject_id = s.id)
      ) order by s.name) from public.subjects s), '[]'::jsonb),
    'topics', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'subjectId', t.subject_id, 'schoolYear', t.school_year, 'name', t.name,
        'worksheetCount', (select count(distinct u.worksheet_id) from usage u where u.topic_id = t.id and u.is_latest),
        'historyWorksheets', coalesce((select jsonb_agg(jsonb_build_object(
            'worksheetId', h.worksheet_id, 'versionNumbers', h.version_numbers, 'live', h.live, 'assigned', h.assigned))
          from (select u.worksheet_id, jsonb_agg(u.version_number order by u.version_number) as version_numbers,
                  bool_or(u.is_live) as live, bool_or(u.is_assigned) as assigned
                from usage u where u.topic_id = t.id
                  and not exists(select 1 from usage c where c.topic_id = t.id and c.worksheet_id = u.worksheet_id and c.is_latest)
                group by u.worksheet_id) h), '[]'::jsonb),
        'inUse', exists(select 1 from usage u where u.topic_id = t.id)
      ) order by t.school_year, t.name) from public.topics t), '[]'::jsonb)
  );
$$;

revoke all on function public.admin_catalogue_overview() from public, anon, authenticated;
grant execute on function public.admin_catalogue_overview() to service_role;

notify pgrst, 'reload schema';
commit;
