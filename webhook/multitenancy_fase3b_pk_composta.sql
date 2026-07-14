-- ============================================================
--  APP VERSATIL — Multi-tenancy: telefone único por empresa
-- ------------------------------------------------------------
--  conversas e funil_clientes usavam "telefone" como chave única
--  GLOBAL (entre todas as empresas). Isso quebra na prática: se um
--  número de WhatsApp tem histórico associado a uma empresa, uma
--  segunda empresa tentando sincronizar uma conversa com esse mesmo
--  número é bloqueada pelo RLS (403) — a linha já "pertence" à
--  outra empresa.
--
--  Este script troca a chave primária de "telefone" sozinho para
--  "(empresa_id, telefone)" — cada empresa passa a ter seu próprio
--  registro independente pro mesmo número de telefone.
--
--  Seguro rodar mais de uma vez (idempotente). Não apaga nenhum
--  dado — só troca a chave primária.
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'conversas_pkey') then
    alter table public.conversas drop constraint conversas_pkey;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'conversas_pkey') then
    alter table public.conversas add constraint conversas_pkey primary key (empresa_id, telefone);
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'funil_clientes_pkey') then
    alter table public.funil_clientes drop constraint funil_clientes_pkey;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'funil_clientes_pkey') then
    alter table public.funil_clientes add constraint funil_clientes_pkey primary key (empresa_id, telefone);
  end if;
end $$;
