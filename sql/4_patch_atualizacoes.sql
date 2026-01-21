-- =========================
-- PATCH: atualizações solicitadas (sem reset)
-- =========================

-- 1) Colaboradores: campos novos
alter table public.colaboradores
  add column if not exists matricula text,
  add column if not exists posto_nome text,
  add column if not exists nr_posto integer,
  add column if not exists id_posto_ref text,
  add column if not exists lotacao text;

create unique index if not exists colaboradores_matricula_uq
on public.colaboradores (matricula)
where matricula is not null and matricula <> '';

-- 2) RPC: find por matrícula
create or replace function public.find_colaborador_by_matricula(p_matricula text)
returns table (id uuid, matricula text, nome text)
language sql
security definer
set search_path = public
as $$
  select c.id, c.matricula, c.nome
  from public.colaboradores c
  where c.ativo = true
    and c.matricula = trim(p_matricula)
  limit 1;
$$;

grant execute on function public.find_colaborador_by_matricula(text) to authenticated;

-- 3) Ocorrências: sequência e campos
create sequence if not exists public.ocorrencia_seq start 1;

alter table public.ocorrencias
  add column if not exists numero bigint;

alter table public.ocorrencias
  alter column numero set default nextval('public.ocorrencia_seq');

create unique index if not exists ocorrencias_numero_uq
on public.ocorrencias (numero);

alter table public.ocorrencias
  add column if not exists substituto text,
  add column if not exists tipo_substituicao text;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='ocorrencias'
      and column_name='total_dias'
  ) then
    alter table public.ocorrencias
      add column total_dias integer
      generated always as ((data_fim - data_inicio) + 1) stored;
  end if;
end $$;
