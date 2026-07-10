-- ============================================================
--  APP VERSATIL — trava as tabelas do Supabase por login
-- ------------------------------------------------------------
--  Depois de rodar este script, NINGUÉM consegue ler ou gravar
--  nada nessas tabelas sem estar logado (Supabase Auth) — nem
--  quem tiver a "anon key" que está no código-fonte do app.
--
--  O webhook (agente de IA 24/7) continua funcionando normalmente
--  porque ele passa a usar a "service_role key", que ignora RLS
--  (configurada como variável de ambiente SUPABASE_SERVICE_ROLE_KEY
--  na Vercel, nunca exposta no navegador).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run. Pode rodar mais de uma vez sem problema.
--
--  IMPORTANTE: só rode isto DEPOIS de:
--   1) criar seu usuário de login em Authentication → Users
--   2) confirmar que o novo index.html (com tela de login) já
--      está publicado e você já conseguiu entrar com ele
--  Rodando antes disso, ninguém (nem você) consegue mais acessar
--  os dados pelo app antigo sem login.
-- ============================================================

alter table public.vendas       enable row level security;
alter table public.compras      enable row level security;
alter table public.despesas     enable row level security;
alter table public.estoque      enable row level security;
alter table public.clientes     enable row level security;
alter table public.fornecedores enable row level security;
alter table public.app_config   enable row level security;

drop policy if exists "somente_logados" on public.vendas;
drop policy if exists "somente_logados" on public.compras;
drop policy if exists "somente_logados" on public.despesas;
drop policy if exists "somente_logados" on public.estoque;
drop policy if exists "somente_logados" on public.clientes;
drop policy if exists "somente_logados" on public.fornecedores;
drop policy if exists "somente_logados" on public.app_config;

create policy "somente_logados" on public.vendas       for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.compras      for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.despesas     for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.estoque      for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.clientes     for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.fornecedores for all to authenticated using (true) with check (true);
create policy "somente_logados" on public.app_config   for all to authenticated using (true) with check (true);
