-- ============================================================
--  APP VERSATIL — Funil de Vendas (Kanban de clientes)
-- ------------------------------------------------------------
--  Uma linha por número de telefone com o estágio atual do
--  cliente no funil de vendas. A IA classifica automaticamente
--  a cada resposta (webhook e app), e o estágio pode ser
--  ajustado manualmente na tela "Funil de Vendas".
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run. Pode rodar mais de uma vez sem problema.
-- ============================================================

create table if not exists public.funil_clientes (
  telefone text primary key,
  nome text,
  estagio text not null default 'novo',
  observacao text,
  convId text,
  updated_at timestamptz default now()
);

alter table public.funil_clientes enable row level security;

drop policy if exists "somente_logados" on public.funil_clientes;
create policy "somente_logados" on public.funil_clientes for all to authenticated using (true) with check (true);
