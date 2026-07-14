-- ============================================================
--  APP VERSATIL — Multi-tenancy, Fase 1b: tabela própria de agendamentos
-- ------------------------------------------------------------
--  PRÉ-REQUISITO: já ter rodado multitenancy_fase0_setup.sql e
--  multitenancy_fase1_rls.sql (usa as funções auth_empresa_id()
--  e set_empresa_id() criadas lá).
--
--  Até agora, "agendamentos" vivia dentro do JSON compartilhado
--  em app_config.data.shared, junto com agentes/canais/brand. Isso
--  foi o que causou a perda de dados: qualquer leitura vazia
--  daquele blob reescrevia TUDO por cima, agendamentos incluído.
--
--  Este script cria uma tabela própria — um registro por
--  agendamento — igual já é feito com "conversas" e
--  "funil_clientes". Vantagens:
--   • o webhook (24/7) passa a poder criar um agendamento sozinho
--     assim que o cliente fecha uma data pelo WhatsApp, sem
--     ninguém precisar estar com o app aberto;
--   • cada agendamento é sua própria linha — criar/editar um nunca
--     arrisca sobrescrever os outros nem qualquer outra config;
--   • já nasce com empresa_id + RLS, dentro do plano de
--     multi-tenancy.
--
--  Seguro rodar mais de uma vez (idempotente).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

create table if not exists public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  conv_id text,
  nome text,
  telefone text,
  quando text,
  data text,
  hora text,
  resumo text,
  origem text not null default 'IA',
  status text not null default 'ativo',
  motivo text,
  gcal_synced boolean not null default false,
  gcal_link text,
  criado_em timestamptz not null default now(),
  alterado_em timestamptz,
  cancelado_em timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.agendamentos enable row level security;

drop trigger if exists trg_set_empresa_id on public.agendamentos;
create trigger trg_set_empresa_id before insert on public.agendamentos
  for each row execute function public.set_empresa_id();

drop policy if exists "somente_logados" on public.agendamentos;
create policy "somente_logados" on public.agendamentos for all to authenticated
  using (empresa_id = public.auth_empresa_id())
  with check (empresa_id = public.auth_empresa_id());
