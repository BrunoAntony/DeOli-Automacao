-- ============================================================
--  APP VERSATIL — Hierarquia de usuários dentro da empresa
-- ------------------------------------------------------------
--  PRÉ-REQUISITO: multitenancy_fase0/fase1/fase2 já rodados.
--
--  Cria dois papéis por usuário (independente do is_admin cross-
--  empresa, que só o bruno tem):
--   • admin        — acesso total à empresa (padrão, ninguém perde
--                    acesso ao rodar este script)
--   • funcionario  — acesso só a Atendimento / Funil / Agendamentos;
--                    bloqueado por RLS (não só escondido na tela)
--                    de vendas, compras, despesas, estoque,
--                    clientes, fornecedores, config do agente e
--                    canais
--
--  Seguro rodar mais de uma vez (idempotente).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

alter table public.app_users add column if not exists role text not null default 'admin';
-- usuário novo criado pelo admin nasce com senha padrão "123" e essa flag em
-- true — o login força a troca de senha antes de liberar o resto do app
alter table public.app_users add column if not exists must_change_password boolean not null default false;

create or replace function public.user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.app_users where id = auth.uid()), 'admin')
$$;

-- tabelas administrativas: só quem é admin (na própria empresa) ou admin cross-empresa
do $$
declare
  t text;
begin
  foreach t in array array['vendas','compras','despesas','estoque','clientes','fornecedores','app_config','canais']
  loop
    execute format('drop policy if exists "somente_logados" on public.%I', t);
    execute format(
      'create policy "somente_logados" on public.%I for all to authenticated using (empresa_id = public.auth_empresa_id() and (public.is_admin() or public.user_role() = ''admin'')) with check (empresa_id = public.auth_empresa_id() and (public.is_admin() or public.user_role() = ''admin''))',
      t
    );
  end loop;
end $$;

-- conversas / funil_clientes / agendamentos continuam abertas pros dois papéis
-- (é literalmente o trabalho do funcionário) — políticas dessas tabelas não mudam aqui.
