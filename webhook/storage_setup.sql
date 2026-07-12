-- ============================================================
--  APP VERSATIL — políticas do Supabase Storage (bucket "catalogo")
-- ------------------------------------------------------------
--  O bucket já foi criado como público (leitura livre, sem
--  precisar de login — é só assim que <img src="..."> funciona).
--  Isso só libera quem pode ENVIAR/apagar arquivo: só usuários
--  logados no app.
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

drop policy if exists "catalogo_authenticated_insert" on storage.objects;
drop policy if exists "catalogo_authenticated_update" on storage.objects;
drop policy if exists "catalogo_authenticated_delete" on storage.objects;

create policy "catalogo_authenticated_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'catalogo');

create policy "catalogo_authenticated_update" on storage.objects
  for update to authenticated using (bucket_id = 'catalogo');

create policy "catalogo_authenticated_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'catalogo');
