begin;

-- Disciplinas para o site público (escolaemdia.me): só as que têm fichas publicadas,
-- com os anos em que existem. Devolve apenas nomes e anos (nada de conteúdo), por isso
-- pode ser chamada com a chave pública (anon) a partir das Pages Functions do site.
create or replace function public.site_subjects()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'years', x.years) order by x.worksheets desc, x.name), '[]'::jsonb)
  from (
    select s.name,
      array_agg(distinct v.school_year order by v.school_year) as years,
      count(distinct w.id) as worksheets
    from public.subjects s
    join public.worksheets w on w.subject_id = s.id and w.status = 'published'
    join public.worksheet_versions v on v.worksheet_id = w.id and v.published_at is not null
    group by s.id, s.name
  ) x;
$$;

revoke all on function public.site_subjects() from public;
grant execute on function public.site_subjects() to anon, authenticated, service_role;

notify pgrst, 'reload schema';
commit;
