-- ============================================================
--  APP VERSATIL — Multi-tenancy, Fase 1: isolamento por empresa (RLS)
-- ------------------------------------------------------------
--  PRÉ-REQUISITO: já ter rodado multitenancy_fase0_setup.sql
--  (cria empresa_id em todas as tabelas + tabela empresas/canais).
--
--  O que este script faz:
--   1) função auth_empresa_id() — descobre a empresa de quem está
--      fazendo a requisição: primeiro tenta uma claim "empresa_id"
--      direto no JWT (é assim que o webhook vai se autenticar na
--      Fase 3), senão resolve pela tabela app_users usando o
--      usuário logado (auth.uid()) — cobre o app normal.
--   2) trigger que preenche empresa_id sozinho em todo INSERT que
--      não mandar esse campo, usando auth_empresa_id() — assim o
--      app não quebra mesmo antes de mandar empresa_id explicito.
--   3) troca todas as políticas "somente_logados" de using(true)
--      pra using(empresa_id = auth_empresa_id()) — daqui pra
--      frente, um usuário só enxerga/edita dado da própria empresa.
--   4) mesma trava no Storage (bucket "catalogo"): só pode
--      enviar/apagar arquivo dentro da própria pasta de empresa.
--
--  A PARTIR DESTE SCRIPT o isolamento passa a valer de verdade.
--  Como só existe 1 empresa até agora ("Versatil", criada no
--  backfill da Fase 0), nada muda na prática pra você — só passa
--  a proteger contra empresas futuras.
--
--  Seguro rodar mais de uma vez (idempotente).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

-- 1) resolve a empresa do usuário/token atual -----------------
create or replace function public.auth_empresa_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(auth.jwt()->>'empresa_id', '')::uuid,
    (select empresa_id from public.app_users where id = auth.uid())
  )
$$;

-- 2) preenche empresa_id sozinho quando o INSERT não mandar -----
create or replace function public.set_empresa_id()
returns trigger
language plpgsql
as $$
begin
  if new.empresa_id is null then
    new.empresa_id := public.auth_empresa_id();
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['app_users','vendas','compras','despesas','estoque','clientes','fornecedores','app_config','conversas','funil_clientes','canais']
  loop
    execute format('drop trigger if exists trg_set_empresa_id on public.%I', t);
    execute format('create trigger trg_set_empresa_id before insert on public.%I for each row execute function public.set_empresa_id()', t);
  end loop;
end $$;

-- 3) políticas por empresa nas tabelas de negócio ----------------
do $$
declare
  t text;
begin
  foreach t in array array['vendas','compras','despesas','estoque','clientes','fornecedores','app_config','conversas','funil_clientes','canais']
  loop
    execute format('drop policy if exists "somente_logados" on public.%I', t);
    execute format('create policy "somente_logados" on public.%I for all to authenticated using (empresa_id = public.auth_empresa_id()) with check (empresa_id = public.auth_empresa_id())', t);
  end loop;
end $$;

-- app_users continua sem nenhuma política (acesso 100% bloqueado
-- via API pública, só service_role acessa) — isso não muda aqui.

-- 4) Storage: só grava/apaga dentro da própria pasta de empresa --
--    (a leitura continua pública, o bucket "catalogo" já é público)
drop policy if exists "catalogo_authenticated_insert" on storage.objects;
drop policy if exists "catalogo_authenticated_update" on storage.objects;
drop policy if exists "catalogo_authenticated_delete" on storage.objects;

create policy "catalogo_authenticated_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'catalogo' and (storage.foldername(name))[1] = public.auth_empresa_id()::text);

create policy "catalogo_authenticated_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'catalogo' and (storage.foldername(name))[1] = public.auth_empresa_id()::text);

create policy "catalogo_authenticated_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'catalogo' and (storage.foldername(name))[1] = public.auth_empresa_id()::text);
