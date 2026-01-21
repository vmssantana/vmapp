-- VMAPP / BRA - Constraints e travas (REEXECUTÁVEL)

-- =========================
-- 0) PRÉ-REQUISITO
-- =========================
-- A tabela public.competencias deve existir.
-- Se você ainda não tem, rode primeiro o 02_rpcs.sql (ou crie a tabela competencias).

-- =========================
-- 1) BLOQUEIO DE SOBREPOSIÇÃO DE OCORRÊNCIAS (por colaborador)
-- =========================
create extension if not exists btree_gist;

-- Coluna de período (inclusivo) para EXCLUDE
alter table public.ocorrencias
  add column if not exists periodo daterange
  generated always as (daterange(data_inicio, data_fim, '[]')) stored;

-- Remove a constraint antiga (se existir) e recria
alter table public.ocorrencias
  drop constraint if exists ocorrencias_no_overlap_por_colab;

alter table public.ocorrencias
  add constraint ocorrencias_no_overlap_por_colab
  exclude using gist (
    colaborador_id with =,
    periodo with &&
  );

-- =========================
-- 2) TRAVA DE COMPETÊNCIA FECHADA NA PLANILHA_LINHAS
-- =========================

-- Função: verifica se a competência está fechada
create or replace function public.is_competencia_fechada(p_competencia date)
returns boolean
language sql
stable
as $$
  select coalesce(
    (select c.status = 'FECHADA'
       from public.competencias c
      where c.competencia = date_trunc('month', p_competencia)::date),
    false
  );
$$;

grant execute on function public.is_competencia_fechada(date) to authenticated;

-- Trigger function: bloqueia escrita se competência fechada
create or replace function public.guard_planilha_competencia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comp date;
begin
  v_comp := date_trunc('month', coalesce(new.competencia, old.competencia))::date;

  if public.is_competencia_fechada(v_comp) then
    raise exception 'Competência % está FECHADA. Edição bloqueada.', v_comp;
  end if;

  return coalesce(new, old);
end;
$$;

-- Remove triggers (se existirem) e recria
drop trigger if exists trg_planilha_guard_ins on public.planilha_linhas;
drop trigger if exists trg_planilha_guard_upd on public.planilha_linhas;
drop trigger if exists trg_planilha_guard_del on public.planilha_linhas;

create trigger trg_planilha_guard_ins
before insert on public.planilha_linhas
for each row execute function public.guard_planilha_competencia();

create trigger trg_planilha_guard_upd
before update on public.planilha_linhas
for each row execute function public.guard_planilha_competencia();

create trigger trg_planilha_guard_del
before delete on public.planilha_linhas
for each row execute function public.guard_planilha_competencia();
