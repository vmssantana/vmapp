-- VMAPP / BRA - RPCs principais

-- Guarda de escrita
create or replace function public.can_write_vmapp()
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.profiles p
    where p.user_id = auth.uid()
      and p.role in ('admin','gestor','operador')
  );
$$;

grant execute on function public.can_write_vmapp() to authenticated;

-- Insert colaborador (CPF criptografado + hash único)
create or replace function public.insert_colaborador(
  p_nome text,
  p_sexo text,
  p_cpf text,
  p_profissao text,
  p_ctps text default null,
  p_serie_ctps text default null,
  p_data_admissao date,
  p_ocupacao public.ocupacao_tipo default 'TITULAR'
)
returns public.colaboradores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.colaboradores;
  v_hash bytea;
  v_enc  bytea;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_nome is null or length(trim(p_nome)) < 3 then
    raise exception 'Nome inválido';
  end if;

  if p_sexo not in ('M','F') then
    raise exception 'Sexo inválido (use M ou F)';
  end if;

  if p_profissao is null or length(trim(p_profissao)) < 2 then
    raise exception 'Profissão inválida';
  end if;

  if p_data_admissao is null then
    raise exception 'Data de admissão obrigatória';
  end if;

  if p_cpf is null or length(public.cpf_normalize(p_cpf)) <> 11 then
    raise exception 'CPF inválido';
  end if;

  v_hash := public.cpf_hash(p_cpf);
  v_enc  := public.cpf_encrypt(p_cpf);

  insert into public.colaboradores(
    nome, sexo, cpf_hash, cpf_enc, profissao, ctps, serie_ctps, data_admissao, ocupacao
  ) values (
    trim(p_nome), p_sexo, v_hash, v_enc, trim(p_profissao), nullif(trim(p_ctps),''), nullif(trim(p_serie_ctps),''), p_data_admissao, p_ocupacao
  )
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'Já existe colaborador com este CPF';
end;
$$;

grant execute on function public.insert_colaborador(text,text,text,text,text,text,date,public.ocupacao_tipo) to authenticated;

-- Buscar colaborador por CPF (sem expor CPF)
create or replace function public.find_colaborador_by_cpf(
  p_cpf text
)
returns setof public.colaboradores
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash bytea;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_cpf is null or length(public.cpf_normalize(p_cpf)) <> 11 then
    raise exception 'CPF inválido';
  end if;

  v_hash := public.cpf_hash(p_cpf);

  return query
  select *
  from public.colaboradores c
  where c.cpf_hash = v_hash
  limit 1;
end;
$$;

grant execute on function public.find_colaborador_by_cpf(text) to authenticated;

-- Gerar ID.Posto
create or replace function public.make_id_posto(
  p_posto_nome text,
  p_nro_posto int,
  p_sequencial int,
  p_contrato text,
  p_ano int
) returns text
language plpgsql
immutable
as $$
declare
  v_posto text;
begin
  v_posto := upper(regexp_replace(trim(coalesce(p_posto_nome,'')), '\s+', '-', 'g'));
  return v_posto || '-' || p_nro_posto || '-' || p_sequencial || '-' || trim(p_contrato) || '-' || p_ano;
end;
$$;

-- Upsert posto
create or replace function public.upsert_posto(
  p_posto_nome text,
  p_nro_posto int,
  p_sequencial int,
  p_contrato text,
  p_ano int,
  p_turno text,
  p_lotacao_macro text default null,
  p_lotacao text default null,
  p_descritivo_lotacao text default null,
  p_cidade text default null,
  p_status public.posto_status default 'PREENCHIDO',
  p_empresa_id uuid default null
)
returns public.postos
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id_posto text;
  v_row public.postos;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_posto_nome is null or length(trim(p_posto_nome)) < 2 then
    raise exception 'Posto (nome) inválido';
  end if;

  if p_nro_posto is null or p_nro_posto < 1 then
    raise exception 'Nº Posto inválido';
  end if;

  if p_sequencial is null or p_sequencial < 1 then
    raise exception 'Sequencial inválido';
  end if;

  if p_contrato is null or length(trim(p_contrato)) < 1 then
    raise exception 'Contrato inválido';
  end if;

  if p_ano is null or p_ano < 2000 then
    raise exception 'Ano inválido';
  end if;

  if p_turno is null or length(trim(p_turno)) < 2 then
    raise exception 'Turno inválido';
  end if;

  v_id_posto := public.make_id_posto(p_posto_nome, p_nro_posto, p_sequencial, p_contrato, p_ano);

  insert into public.postos(
    posto_nome, nro_posto, nro_sequencial, id_posto, turno,
    lotacao_macro, lotacao, descritivo_lotacao, cidade, status, empresa_id
  ) values (
    trim(p_posto_nome), p_nro_posto, p_sequencial, v_id_posto, trim(p_turno),
    nullif(trim(p_lotacao_macro),''), nullif(trim(p_lotacao),''), nullif(trim(p_descritivo_lotacao),''), nullif(trim(p_cidade),''), p_status, p_empresa_id
  )
  on conflict (id_posto) do update set
    turno = excluded.turno,
    lotacao_macro = excluded.lotacao_macro,
    lotacao = excluded.lotacao,
    descritivo_lotacao = excluded.descritivo_lotacao,
    cidade = excluded.cidade,
    status = excluded.status,
    empresa_id = excluded.empresa_id,
    updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.upsert_posto(text,int,int,text,int,text,text,text,text,text,public.posto_status,uuid) to authenticated;

-- Registrar ocorrência
create or replace function public.registrar_ocorrencia(
  p_colaborador_id uuid,
  p_posto_id uuid,
  p_data_inicio date,
  p_data_fim date,
  p_motivo text,
  p_motivo_descritivo text default null,
  p_substituicao int default null,
  p_substituto_colaborador_id uuid default null
)
returns public.ocorrencias
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.ocorrencias;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_colaborador_id is null then raise exception 'Colaborador obrigatório'; end if;
  if p_posto_id is null then raise exception 'Posto obrigatório'; end if;
  if p_data_inicio is null or p_data_fim is null then raise exception 'Período obrigatório'; end if;
  if p_data_fim < p_data_inicio then raise exception 'Data fim não pode ser anterior ao início'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 2 then raise exception 'Motivo obrigatório'; end if;

  insert into public.ocorrencias(
    colaborador_id, posto_id, data_inicio, data_fim, motivo, motivo_descritivo,
    substituicao, substituto_colaborador_id
  ) values (
    p_colaborador_id, p_posto_id, p_data_inicio, p_data_fim, trim(p_motivo), nullif(trim(p_motivo_descritivo),''),
    p_substituicao, p_substituto_colaborador_id
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.registrar_ocorrencia(uuid,uuid,date,date,text,text,int,uuid) to authenticated;

-- Transferir colaborador de posto (histórico)
create or replace function public.transferir_colaborador_posto(
  p_colaborador_id uuid,
  p_posto_destino_id uuid,
  p_data_entrada date,
  p_ocupacao public.ocupacao_tipo default 'TITULAR',
  p_observacao text default null
)
returns public.alocacoes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ativa public.alocacoes;
  v_conflict int;
  v_nova public.alocacoes;
  v_posto_origem uuid;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_colaborador_id is null then raise exception 'Colaborador obrigatório'; end if;
  if p_posto_destino_id is null then raise exception 'Posto destino obrigatório'; end if;
  if p_data_entrada is null then raise exception 'Data de entrada obrigatória'; end if;

  select * into v_ativa
  from public.alocacoes a
  where a.colaborador_id = p_colaborador_id
    and a.data_saida is null
  order by a.data_entrada desc
  limit 1;

  if v_ativa.id is not null then
    v_posto_origem := v_ativa.posto_id;

    update public.alocacoes
    set data_saida = (p_data_entrada - 1)
    where id = v_ativa.id;

    update public.postos
    set status = 'VAGO', updated_at = now()
    where id = v_posto_origem;
  end if;

  if p_ocupacao = 'TITULAR' then
    select count(*) into v_conflict
    from public.alocacoes a
    where a.posto_id = p_posto_destino_id
      and a.data_saida is null
      and a.ocupacao = 'TITULAR';

    if v_conflict > 0 then
      raise exception 'Posto destino já possui TITULAR ativo';
    end if;
  end if;

  insert into public.alocacoes(
    colaborador_id, posto_id, data_entrada, ocupacao, observacao
  ) values (
    p_colaborador_id, p_posto_destino_id, p_data_entrada, p_ocupacao, nullif(trim(p_observacao),'')
  )
  returning * into v_nova;

  update public.postos
  set status = 'PREENCHIDO', updated_at = now()
  where id = p_posto_destino_id;

  return v_nova;
end;
$$;

grant execute on function public.transferir_colaborador_posto(uuid,uuid,date,public.ocupacao_tipo,text) to authenticated;

-- Tipo para importação em lote
do $$ begin
  create type public.planilha_linha_input as (
    competencia date,
    terceirizado text,
    sexo text,
    cpf text,
    profissao text,
    data_admissao date,
    ctps text,
    serie_ctps text,
    ocupacao public.ocupacao_tipo,
    posto text,
    nro_posto int,
    nro_sequencial_posto int,
    id_posto text,
    turno text,
    data_entrada_posto date,
    data_saida_posto date,
    dias_trabalhados int,
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
    cidade text
  );
exception when duplicate_object then null; end $$;

-- Importação em lote
create or replace function public.import_planilha_linhas(
  p_linhas public.planilha_linha_input[]
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
  r public.planilha_linha_input;
  v_hash bytea;
begin
  if not public.can_write_vmapp() then
    raise exception 'Sem permissão';
  end if;

  if p_linhas is null or array_length(p_linhas,1) is null then
    return 0;
  end if;

  foreach r in array p_linhas loop
    if r.competencia is null then
      raise exception 'Competência obrigatória';
    end if;

    if r.cpf is null or length(public.cpf_normalize(r.cpf)) <> 11 then
      raise exception 'CPF inválido na importação';
    end if;

    v_hash := public.cpf_hash(r.cpf);

    insert into public.planilha_linhas(
      competencia,
      terceirizado, sexo, cpf_hash, profissao, data_admissao, ctps, serie_ctps, ocupacao,
      posto, nro_posto, nro_sequencial_posto, id_posto, turno,
      data_entrada_posto, data_saida_posto,
      dias_trabalhados,
      data_inicio_afastamento, data_fim_afastamento, motivo_afastamento, motivo_descritivo, substituicao,
      empresa, cnpj, nro_contrato, ano_contrato, nro_aditivo, data_inicio_vigencia, data_fim_vigencia,
      lotacao_macro, lotacao, descritivo_lotacao, cidade
    ) values (
      r.competencia,
      trim(r.terceirizado), r.sexo, v_hash, trim(r.profissao), r.data_admissao, nullif(trim(r.ctps),''), nullif(trim(r.serie_ctps),''), coalesce(r.ocupacao,'TITULAR'),
      trim(r.posto), r.nro_posto, coalesce(r.nro_sequencial_posto,1), trim(r.id_posto), nullif(trim(r.turno),''),
      r.data_entrada_posto, r.data_saida_posto,
      coalesce(r.dias_trabalhados,0),
      r.data_inicio_afastamento, r.data_fim_afastamento, nullif(trim(r.motivo_afastamento),''), nullif(trim(r.motivo_descritivo),''), r.substituicao,
      nullif(trim(r.empresa),''), nullif(trim(r.cnpj),''), nullif(trim(r.nro_contrato),''), r.ano_contrato, nullif(trim(r.nro_aditivo),''), r.data_inicio_vigencia, r.data_fim_vigencia,
      nullif(trim(r.lotacao_macro),''), nullif(trim(r.lotacao),''), nullif(trim(r.descritivo_lotacao),''), nullif(trim(r.cidade),'')
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.import_planilha_linhas(public.planilha_linha_input[]) to authenticated;

-- Competências
create table if not exists public.competencias (
  competencia date primary key,
  status text not null check (status in ('ABERTA','FECHADA')) default 'ABERTA',
  fechado_em timestamptz,
  fechado_por uuid references auth.users(id) on delete set null,
  observacao text,
  created_at timestamptz not null default now()
);

alter table public.competencias enable row level security;

drop policy if exists "competencias_read_auth" on public.competencias;
create policy "competencias_read_auth"
on public.competencias for select
to authenticated
using (true);

drop policy if exists "competencias_write_admin_gestor" on public.competencias;
create policy "competencias_write_admin_gestor"
on public.competencias for all
to authenticated
using (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor'))
)
with check (
  exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor'))
);

create or replace function public.open_competencia(p_competencia date)
returns public.competencias
language plpgsql
security definer
set search_path = public
as $$
declare v public.competencias;
begin
  if not exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor')) then
    raise exception 'Sem permissão';
  end if;

  if p_competencia is null then raise exception 'Competência obrigatória'; end if;

  insert into public.competencias(competencia,status)
  values (date_trunc('month', p_competencia)::date, 'ABERTA')
  on conflict (competencia) do update set status='ABERTA', fechado_em=null, fechado_por=null
  returning * into v;

  return v;
end;
$$;

grant execute on function public.open_competencia(date) to authenticated;

create or replace function public.close_competencia(p_competencia date, p_observacao text default null)
returns public.competencias
language plpgsql
security definer
set search_path = public
as $$
declare v public.competencias;
begin
  if not exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('admin','gestor')) then
    raise exception 'Sem permissão';
  end if;

  if p_competencia is null then raise exception 'Competência obrigatória'; end if;

  insert into public.competencias(competencia,status,fechado_em,fechado_por,observacao)
  values (date_trunc('month', p_competencia)::date, 'FECHADA', now(), auth.uid(), nullif(trim(p_observacao),'') )
  on conflict (competencia) do update set
    status='FECHADA', fechado_em=now(), fechado_por=auth.uid(), observacao=excluded.observacao
  returning * into v;

  return v;
end;
$$;

grant execute on function public.close_competencia(date,text) to authenticated;
