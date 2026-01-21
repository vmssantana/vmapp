-- VMAPP / BRA - Schema base
create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('admin','gestor','operador');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ocupacao_tipo as enum ('TITULAR','VOLANTE','VAGO','FALTA','TITULAR-DESLIGADO');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.posto_status as enum ('VAGO','PREENCHIDO');
exception when duplicate_object then null; end $$;

-- Perfis (Auth)
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role public.user_role not null default 'operador',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "profiles_admin_all" on public.profiles;
create policy "profiles_admin_all"
on public.profiles for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role = 'admin')
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role = 'admin')
);

-- Empresas
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  razao_social text not null,
  cnpj text not null,
  nro_contrato text not null,
  ano_contrato int not null,
  nro_aditivo text,
  vigencia_inicio date not null,
  vigencia_fim date not null,
  sequencial int not null default 1,
  created_at timestamptz not null default now(),
  unique (cnpj, nro_contrato, ano_contrato, sequencial)
);

alter table public.empresas enable row level security;

drop policy if exists "empresas_read_auth" on public.empresas;
create policy "empresas_read_auth"
on public.empresas for select
to authenticated
using (true);

drop policy if exists "empresas_write_admin_gestor" on public.empresas;
create policy "empresas_write_admin_gestor"
on public.empresas for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor'))
);

drop policy if exists "empresas_update_admin_gestor" on public.empresas;
create policy "empresas_update_admin_gestor"
on public.empresas for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor'))
);

-- Funções CPF
create or replace function public.cpf_normalize(p_cpf text)
returns text language sql immutable as $$
  select regexp_replace(coalesce(p_cpf,''), '[^0-9]', '', 'g');
$$;

create or replace function public.cpf_hash(p_cpf text)
returns bytea language sql immutable as $$
  select digest(public.cpf_normalize(p_cpf), 'sha256');
$$;

create or replace function public.cpf_encrypt(p_cpf text)
returns bytea language plpgsql as $$
declare
  k text := current_setting('app.cpf_key', true);
begin
  if k is null or length(k) < 12 then
    raise exception 'Defina a chave: set app.cpf_key = ''UMA_CHAVE_FORTE...''';
  end if;
  return pgp_sym_encrypt(public.cpf_normalize(p_cpf), k, 'compress-algo=1,cipher-algo=aes256');
end;
$$;

-- Colaboradores
create table if not exists public.colaboradores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  sexo text not null check (sexo in ('M','F')),
  cpf_hash bytea not null unique,
  cpf_enc bytea not null,
  profissao text not null,
  ctps text,
  serie_ctps text,
  data_admissao date not null,
  ocupacao public.ocupacao_tipo not null default 'TITULAR',
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_colaboradores_touch on public.colaboradores;
create trigger trg_colaboradores_touch
before update on public.colaboradores
for each row execute function public.touch_updated_at();

alter table public.colaboradores enable row level security;

drop policy if exists "colaboradores_read_auth" on public.colaboradores;
create policy "colaboradores_read_auth"
on public.colaboradores for select
to authenticated
using (true);

drop policy if exists "colaboradores_write_roles" on public.colaboradores;
create policy "colaboradores_write_roles"
on public.colaboradores for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

drop policy if exists "colaboradores_update_roles" on public.colaboradores;
create policy "colaboradores_update_roles"
on public.colaboradores for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

-- Postos
create table if not exists public.postos (
  id uuid primary key default gen_random_uuid(),
  posto_nome text not null,
  nro_posto int not null,
  nro_sequencial int not null default 1,
  id_posto text not null unique,
  turno text not null,
  lotacao_macro text,
  lotacao text,
  descritivo_lotacao text,
  cidade text,
  status public.posto_status not null default 'PREENCHIDO',
  empresa_id uuid references public.empresas(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_postos_touch on public.postos;
create trigger trg_postos_touch
before update on public.postos
for each row execute function public.touch_updated_at();

alter table public.postos enable row level security;

drop policy if exists "postos_read_auth" on public.postos;
create policy "postos_read_auth"
on public.postos for select
to authenticated
using (true);

drop policy if exists "postos_write_roles" on public.postos;
create policy "postos_write_roles"
on public.postos for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

drop policy if exists "postos_update_roles" on public.postos;
create policy "postos_update_roles"
on public.postos for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

-- Alocações
create table if not exists public.alocacoes (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid references public.colaboradores(id) on delete restrict,
  posto_id uuid references public.postos(id) on delete restrict,
  data_entrada date not null,
  data_saida date,
  ocupacao public.ocupacao_tipo not null default 'TITULAR',
  observacao text,
  created_at timestamptz not null default now()
);

alter table public.alocacoes enable row level security;

drop policy if exists "alocacoes_read_auth" on public.alocacoes;
create policy "alocacoes_read_auth"
on public.alocacoes for select
to authenticated
using (true);

drop policy if exists "alocacoes_write_roles" on public.alocacoes;
create policy "alocacoes_write_roles"
on public.alocacoes for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

drop policy if exists "alocacoes_update_roles" on public.alocacoes;
create policy "alocacoes_update_roles"
on public.alocacoes for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

-- Ocorrências
create table if not exists public.ocorrencias (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid references public.colaboradores(id) on delete restrict,
  posto_id uuid references public.postos(id) on delete restrict,
  data_inicio date not null,
  data_fim date not null,
  motivo text not null,
  motivo_descritivo text,
  substituicao int,
  substituto_colaborador_id uuid references public.colaboradores(id) on delete set null,
  created_at timestamptz not null default now(),
  check (data_fim >= data_inicio)
);

alter table public.ocorrencias enable row level security;

drop policy if exists "ocorrencias_read_auth" on public.ocorrencias;
create policy "ocorrencias_read_auth"
on public.ocorrencias for select
to authenticated
using (true);

drop policy if exists "ocorrencias_write_roles" on public.ocorrencias;
create policy "ocorrencias_write_roles"
on public.ocorrencias for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

drop policy if exists "ocorrencias_update_roles" on public.ocorrencias;
create policy "ocorrencias_update_roles"
on public.ocorrencias for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

-- Planilha (espelho)
create table if not exists public.planilha_linhas (
  id uuid primary key default gen_random_uuid(),
  competencia date not null,
  terceirizado text not null,
  sexo text not null,
  cpf_hash bytea not null,
  profissao text not null,
  data_admissao date not null,
  ctps text,
  serie_ctps text,
  ocupacao public.ocupacao_tipo not null,
  posto text not null,
  nro_posto int not null,
  nro_sequencial_posto int not null default 1,
  id_posto text not null,
  turno text,
  data_entrada_posto date,
  data_saida_posto date,
  dias_trabalhados int not null default 0,
  data_inicio_afastamento date,
  data_fim_afastamento date,
  motivo_afastamento text,
  motivo_descritivo text,
  substituicao int,
  empresa text,
  cnpj text,
  nro_contrato text,
  ano_contrato int,
  nro_aditivo text,
  data_inicio_vigencia date,
  data_fim_vigencia date,
  lotacao_macro text,
  lotacao text,
  descritivo_lotacao text,
  cidade text,
  created_at timestamptz not null default now()
);

alter table public.planilha_linhas enable row level security;

drop policy if exists "planilha_read_auth" on public.planilha_linhas;
create policy "planilha_read_auth"
on public.planilha_linhas for select
to authenticated
using (true);

drop policy if exists "planilha_write_roles" on public.planilha_linhas;
create policy "planilha_write_roles"
on public.planilha_linhas for insert
to authenticated
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

drop policy if exists "planilha_update_roles" on public.planilha_linhas;
create policy "planilha_update_roles"
on public.planilha_linhas for update
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor','operador'))
);

-- Views
create or replace view public.v_planilha_com_somatorio as
select
  pl.*,
  (
    select coalesce(sum(pl2.dias_trabalhados),0)
    from public.planilha_linhas pl2
    where pl2.competencia = pl.competencia
      and pl2.id_posto = pl.id_posto
  ) as somatorio_dias
from public.planilha_linhas pl;

create or replace view public.v_alertas_afastamentos_7d as
select
  o.*,
  (o.data_fim - current_date) as dias_para_termino
from public.ocorrencias o
where o.data_fim between current_date and (current_date + 7);

-- Função dias corridos na competência (inclusivo)
create or replace function public.dias_corridos_na_competencia(
  p_competencia date,
  p_inicio date,
  p_fim date
) returns int language plpgsql immutable as $$
declare
  mes_inicio date := date_trunc('month', p_competencia)::date;
  mes_fim date := (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date;
  i date;
  f date;
begin
  if p_inicio is null or p_fim is null then return 0; end if;
  i := greatest(p_inicio, mes_inicio);
  f := least(p_fim, mes_fim);
  if f < i then return 0; end if;
  return (f - i) + 1;
end;
$$;
