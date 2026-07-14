-- ============================================================
--  APP VERSATIL — Multi-tenancy, Fase 2: usuário admin multi-empresa
-- ------------------------------------------------------------
--  PRÉ-REQUISITO: multitenancy_fase0_setup.sql e
--  multitenancy_fase1_rls.sql já rodados (usa auth_empresa_id()).
--
--  O que este script faz:
--   1) adiciona is_admin em app_users e marca o usuário "bruno"
--      como admin — admin consegue ver/trocar entre TODAS as
--      empresas (as demais pessoas continuam presas à própria
--      empresa, sem mudança nenhuma pra elas);
--   2) função is_admin() (mesmo espírito de auth_empresa_id());
--   3) liga RLS na tabela "empresas" — ela ficou sem nenhuma
--      política desde a Fase 0 (falha minha), então até agora
--      qualquer usuário logado conseguia listar o nome de TODAS
--      as empresas via API pública. Agora: cada um só vê a
--      própria empresa, exceto admin, que vê todas; só admin
--      pode criar/editar empresa;
--   4) cadastra a empresa "DeOli Automações".
--
--  Seguro rodar mais de uma vez (idempotente).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

alter table public.app_users add column if not exists is_admin boolean not null default false;

update public.app_users set is_admin = true where username = 'bruno';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_admin from public.app_users where id = auth.uid()), false)
$$;

alter table public.empresas enable row level security;

drop policy if exists "leitura_propria_ou_admin" on public.empresas;
create policy "leitura_propria_ou_admin" on public.empresas for select to authenticated
  using (id = public.auth_empresa_id() or public.is_admin());

drop policy if exists "criacao_somente_admin" on public.empresas;
create policy "criacao_somente_admin" on public.empresas for insert to authenticated
  with check (public.is_admin());

drop policy if exists "edicao_somente_admin" on public.empresas;
create policy "edicao_somente_admin" on public.empresas for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

insert into public.empresas (nome)
select 'DeOli Automações'
where not exists (select 1 from public.empresas where nome = 'DeOli Automações');
