begin;

-- Resumo de todas as fichas (versão mais recente) para a «Migração» do admin comparar dois ambientes
-- (ex.: staging → produção) sem descarregar o conteúdo de cada ficha.
-- Ligação entre ambientes pelo nome: disciplina + ano + título; temas e conteúdos da grade também pelo nome.
-- contentHash: md5 do jsonb em texto (forma canónica do jsonb, igual em qualquer base para o mesmo conteúdo).

create or replace function public.admin_worksheet_digests()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', w.id, 'subject', s.name, 'title', w.title, 'status', w.status, 'accessTier', w.access_tier,
      'schoolYear', v.school_year, 'versionNumber', v.version_number, 'published', v.published_at is not null,
      'contentHash', md5(v.content_json::text),
      'questionCount', jsonb_array_length(v.content_json->'questions'),
      'imageCount', (select count(*) from jsonb_array_elements(v.content_json->'questions') q
                     where nullif(q->'image'->>'path', '') is not null),
      'topics', coalesce((select jsonb_agg(t.name order by t.name)
                          from public.worksheet_version_topics vt join public.topics t on t.id = vt.topic_id
                          where vt.worksheet_version_id = v.id), '[]'::jsonb),
      'contents', coalesce((select jsonb_agg(jsonb_build_object('topic', t.name, 'name', c.name, 'semester', c.semester)
                                             order by t.name, c.name)
                            from public.worksheet_contents wc
                            join public.topic_contents c on c.id = wc.content_id
                            join public.topics t on t.id = c.topic_id
                            where wc.worksheet_id = w.id), '[]'::jsonb)
    ) order by s.name, v.school_year, w.title), '[]'::jsonb)
  from public.worksheets w
  join public.subjects s on s.id = w.subject_id
  join lateral (select x.* from public.worksheet_versions x where x.worksheet_id = w.id
                order by x.version_number desc limit 1) v on true;
$$;

revoke all on function public.admin_worksheet_digests() from public, anon, authenticated;
grant execute on function public.admin_worksheet_digests() to service_role;

notify pgrst, 'reload schema';
commit;
