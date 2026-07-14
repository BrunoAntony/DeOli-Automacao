-- ============================================================
--  APP VERSATIL — Multi-tenancy, Fase 0: schema + backfill
-- ------------------------------------------------------------
--  Prepara o banco pra várias empresas usarem o mesmo Supabase:
--   1) tabela "empresas" (uma linha por empresa/cliente)
--   2) tabela "canais" (credenciais uazapi por empresa — hoje
--      isso vive dentro do JSON em app_config.data.canais)
--   3) coluna empresa_id em todas as tabelas de dados do negócio
--   4) migra tudo que já existe pra uma empresa "Versatil"
--      (a empresa atual), sem apagar nada
--
--  Depois deste script, o RLS antigo continua valendo
--  (using(true) to authenticated) — ou seja, NADA muda no
--  comportamento do app ainda. O isolamento de verdade só entra
--  em vigor depois de rodar o próximo script (fase1_rls.sql).
--
--  Seguro rodar mais de uma vez (idempotente).
--
--  Como rodar: Supabase → seu projeto → SQL Editor → cole tudo
--  abaixo → Run.
-- ============================================================

create extension if not exists pgcrypto;

-- 1) empresas (tenants) -----------------------------------------
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  status text not null default 'ativo',
  created_at timestamptz default now()
);

-- 2) canais (uma linha por instância WhatsApp/uazapi por empresa)
create table if not exists public.canais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  nome text,
  uazapi_base_url text,
  uazapi_instance_token text,
  webhook_key text unique not null default encode(gen_random_bytes(16), 'hex'),
  created_at timestamptz default now()
);

alter table public.canais enable row level security;
drop policy if exists "somente_logados" on public.canais;
create policy "somente_logados" on public.canais for all to authenticated using (true) with check (true);

-- 3) coluna empresa_id nas tabelas de dados do negócio -----------
alter table public.app_users      add column if not exists empresa_id uuid;
alter table public.vendas         add column if not exists empresa_id uuid;
alter table public.compras        add column if not exists empresa_id uuid;
alter table public.despesas       add column if not exists empresa_id uuid;
alter table public.estoque        add column if not exists empresa_id uuid;
alter table public.clientes       add column if not exists empresa_id uuid;
alter table public.fornecedores   add column if not exists empresa_id uuid;
alter table public.conversas      add column if not exists empresa_id uuid;
alter table public.funil_clientes add column if not exists empresa_id uuid;
alter table public.app_config     add column if not exists empresa_id uuid;

-- 4) backfill: cria (ou reaproveita) a empresa "Versatil" e ------
--    aponta todo dado existente pra ela, sem perder nada
do $$
declare
  v_empresa_id uuid;
begin
  select id into v_empresa_id from public.empresas where nome = 'Versatil' limit 1;
  if v_empresa_id is null then
    insert into public.empresas (nome) values ('Versatil') returning id into v_empresa_id;
  end if;

  update public.app_users      set empresa_id = v_empresa_id where empresa_id is null;
  update public.vendas         set empresa_id = v_empresa_id where empresa_id is null;
  update public.compras        set empresa_id = v_empresa_id where empresa_id is null;
  update public.despesas       set empresa_id = v_empresa_id where empresa_id is null;
  update public.estoque        set empresa_id = v_empresa_id where empresa_id is null;
  update public.clientes       set empresa_id = v_empresa_id where empresa_id is null;
  update public.fornecedores   set empresa_id = v_empresa_id where empresa_id is null;
  update public.conversas      set empresa_id = v_empresa_id where empresa_id is null;
  update public.funil_clientes set empresa_id = v_empresa_id where empresa_id is null;
  update public.app_config     set empresa_id = v_empresa_id where empresa_id is null;

  -- migra os canais que hoje vivem dentro de app_config.data.canais (JSON,
  -- linha id='shared') pra tabela "canais" própria, gerando um webhook_key
  -- novo pra cada instância uazapi já cadastrada
  insert into public.canais (empresa_id, nome, uazapi_base_url, uazapi_instance_token)
  select
    v_empresa_id,
    coalesce(c->>'nome', 'Principal'),
    nullif(c->'uazapi'->>'baseUrl', ''),
    nullif(c->'uazapi'->>'instanceToken', '')
  from public.app_config ac,
       jsonb_array_elements(coalesce(ac.data->'canais', '[]'::jsonb)) as c
  where ac.id = 'shared'
    and ac.empresa_id = v_empresa_id
    and nullif(c->'uazapi'->>'instanceToken', '') is not null
    and not exists (
      select 1 from public.canais existing
      where existing.empresa_id = v_empresa_id
        and existing.uazapi_instance_token = c->'uazapi'->>'instanceToken'
    );
end $$;

-- 5) trava empresa_id como obrigatório + referencia empresas -----
alter table public.app_users      alter column empresa_id set not null;
alter table public.vendas         alter column empresa_id set not null;
alter table public.compras        alter column empresa_id set not null;
alter table public.despesas       alter column empresa_id set not null;
alter table public.estoque        alter column empresa_id set not null;
alter table public.clientes       alter column empresa_id set not null;
alter table public.fornecedores   alter column empresa_id set not null;
alter table public.conversas      alter column empresa_id set not null;
alter table public.funil_clientes alter column empresa_id set not null;
alter table public.app_config     alter column empresa_id set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'app_users_empresa_id_fkey') then
    alter table public.app_users add constraint app_users_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vendas_empresa_id_fkey') then
    alter table public.vendas add constraint vendas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'compras_empresa_id_fkey') then
    alter table public.compras add constraint compras_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'despesas_empresa_id_fkey') then
    alter table public.despesas add constraint despesas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'estoque_empresa_id_fkey') then
    alter table public.estoque add constraint estoque_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'clientes_empresa_id_fkey') then
    alter table public.clientes add constraint clientes_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fornecedores_empresa_id_fkey') then
    alter table public.fornecedores add constraint fornecedores_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'conversas_empresa_id_fkey') then
    alter table public.conversas add constraint conversas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'funil_clientes_empresa_id_fkey') then
    alter table public.funil_clientes add constraint funil_clientes_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_config_empresa_id_fkey') then
    alter table public.app_config add constraint app_config_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
  end if;
end $$;

-- 6) app_config: troca a chave primária de (id) para (empresa_id, id)
--    hoje "id" é só um rótulo fixo ('shared'/'produtos_catalogo'/
--    'webhook_agent') repetido por empresa, então precisa da
--    empresa_id na chave pra não colidir entre empresas
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'app_config_pkey') then
    alter table public.app_config drop constraint app_config_pkey;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_config_pkey') then
    alter table public.app_config add constraint app_config_pkey primary key (empresa_id, id);
  end if;
end $$;
