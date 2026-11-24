begin;

-- Imagens das questões das fichas.
-- Bucket público: o app mostra a imagem pelo URL público, sem login.
-- Só o admin envia/apaga (via service_role, que ignora RLS) — não há políticas de escrita
-- para anon/authenticated, por isso ninguém mais consegue alterar o bucket.
-- Os ficheiros não se apagam ao editar uma ficha: versões antigas continuam a apontar para eles.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'question-images',
  'question-images',
  true,
  2097152, -- 2 MB
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
