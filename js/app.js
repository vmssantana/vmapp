(function () {
  "use strict";

  // Evita carregar duas vezes
  if (window.__VMAPP_LOADED__) return;
  window.__VMAPP_LOADED__ = true;

  const $ = (q) => document.querySelector(q);
  function showMsg(selector, text, ms = 6000) {
    const el = document.querySelector(selector);
    if (!el) { console.warn('MSG target not found:', selector, text); return; }
    el.style.display = 'block';
    el.textContent = text;
    clearTimeout(el.__t);
    el.__t = setTimeout(() => { el.style.display = 'none'; }, ms);
  }

  function showView(name) {
    document.querySelectorAll(".view").forEach((v) => (v.style.display = "none"));
    const el = $(`#view-${name}`);
    if (el) el.style.display = "block";
  }

  document.querySelectorAll("[data-view]").forEach((btn) => {
    btn.addEventListener("click", () => showView(btn.dataset.view));
  });

  function cpfNormalize(v) { return (v || "").replace(/\D/g, ""); }

  // =========================
  // AUTH UI
  // =========================
  async function refreshAuthUI() {
    const { data } = await window.supabase.auth.getSession();
    const logged = !!data?.session;

    $("#authState").textContent = logged ? "Conectado" : "Desconectado";
    $("#btnLogin").style.display = logged ? "none" : "inline-block";
    $("#btnLogout").style.display = logged ? "inline-block" : "none";

    return logged;
  }

  $("#btnLogin")?.addEventListener("click", async () => {
    const email = prompt("Email:");
    const password = prompt("Senha:");
    if (!email || !password) return;

    const { error } = await window.supabase.auth.signInWithPassword({ email, password });
    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    const logged = await refreshAuthUI();
    if (logged) await loadDashboard();
  });

  $("#btnLogout")?.addEventListener("click", async () => {
    await window.supabase.auth.signOut();
    await refreshAuthUI();
  });

  window.supabase.auth.onAuthStateChange(async () => {
    const logged = await refreshAuthUI();
    if (logged) await loadDashboard();
  });

  // =========================
  // DASHBOARD
  // =========================
  async function loadDashboard() {
    const [colabs, postos, alertas] = await Promise.all([
      window.supabase.from("colaboradores").select("id", { count: "exact", head: true }).eq("ativo", true),
      window.supabase.from("postos").select("id", { count: "exact", head: true }).eq("status", "PREENCHIDO"),
      window.supabase.from("v_alertas_afastamentos_7d").select("*"),
    ]);

    $("#kpiColab").textContent = colabs.count ?? "0";
    $("#kpiPostosOk").textContent = postos.count ?? "0";
    $("#kpiAlertas").textContent = alertas.data?.length ?? "0";

    const tbody = $("#tblAlertas tbody");
    tbody.innerHTML = "";

    (alertas.data || []).forEach((a) => {
      const dias = Number(a.dias_para_termino ?? 999);
      const badge = dias <= 1 ? "danger" : dias <= 3 ? "warn" : "ok";
      tbody.insertAdjacentHTML(
        "beforeend",
        `<tr>
          <td>${a.colaborador_id ?? "-"}</td>
          <td>${a.posto_id ?? "-"}</td>
          <td>${a.motivo ?? "-"}</td>
          <td>${a.data_fim ?? "-"}</td>
          <td><span class="badge ${badge}">${badge.toUpperCase()}</span></td>
        </tr>`
      );
    });
  }

  // =========================
  // COLABORADORES
  // =========================
  function buildColabIdPosto() {
    const posto = ($("#cPostoNome")?.value || "").trim().toLowerCase().replace(/\s+/g, "-");
    const nr = ($("#cNrPosto")?.value || "").toString().trim();
    const suffix = "1-2-2023";
    const out = posto && nr ? `${posto}-${nr}-${suffix}` : "";
    if ($("#cIdPosto")) $("#cIdPosto").value = out;
    return out;
  }

  function fillCtpsSerieFromCpf() {
    const cpf = cpfNormalize($("#cCpf")?.value || "");
    if (cpf.length === 11) {
      $("#cCtps").value = cpf.slice(0, 7);
      $("#cSerie").value = cpf.slice(-4);
    } else {
      $("#cCtps").value = "";
      $("#cSerie").value = "";
    }
  }

  async function loadLotacoesIntoSelect() {
    const sel = $("#cLotacao");
    if (!sel) return;
    sel.innerHTML = `<option value="">Carregando...</option>`;

    const { data, error } = await window.supabase
      .from("postos")
      .select("lotacao")
      .not("lotacao", "is", null);

    if (error) {
      console.warn(error);
      sel.innerHTML = `<option value="">(erro ao carregar)</option>`;
      return;
    }

    const lotacoes = [...new Set((data || []).map(x => (x.lotacao || "").trim()).filter(Boolean))].sort();
    sel.innerHTML = `<option value="">Selecione...</option>` +
      lotacoes.map(l => `<option value="${l}">${l}</option>`).join("");
  }

  function clearColabForm() {
    $("#cId").value = "";
    $("#cMatricula").value = "";
    $("#cNome").value = "";
    $("#cCpf").value = "";
    $("#cSexo").value = "M";
    $("#cProfissao").value = "";
    $("#cPostoNome").value = "";
    $("#cNrPosto").value = "";
    $("#cIdPosto").value = "";
    $("#cLotacao").value = "";
    $("#cAdmissao").value = "";
    $("#cOcupacao").value = "TITULAR";
    fillCtpsSerieFromCpf();
  }

  async function listColaboradores() {
    const tbody = $("#tblColab tbody");
    if (!tbody) return;

    const { data, error } = await window.supabase
      .from("colaboradores")
      .select("id, matricula, nome, profissao, posto_nome, nr_posto, id_posto_ref, lotacao, ocupacao, ativo")
      .neq("ativo", false)   // inclui true e null, exclui apenas false
      .order("nome", { ascending: true })
      .limit(300);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    tbody.innerHTML = "";
    (data || []).forEach(c => {
      const tr = document.createElement("tr");
      tr.style.cursor = "pointer";
      tr.innerHTML = `
        <td>${c.matricula ?? ""}</td>
        <td>${c.nome ?? ""}</td>
        <td>${c.profissao ?? ""}</td>
        <td>${c.posto_nome ?? ""}</td>
        <td>${c.nr_posto ?? ""}</td>
        <td>${c.id_posto_ref ?? ""}</td>
        <td>${c.lotacao ?? ""}</td>
        <td>${c.ocupacao ?? ""}</td>
      `;
      tr.addEventListener("click", () => {
        $("#cId").value = c.id;
        $("#cMatricula").value = c.matricula ?? "";
        $("#cNome").value = c.nome ?? "";
        $("#cProfissao").value = c.profissao ?? "";
        $("#cPostoNome").value = c.posto_nome ?? "";
        $("#cNrPosto").value = c.nr_posto ?? "";
        $("#cIdPosto").value = c.id_posto_ref ?? "";
        $("#cLotacao").value = c.lotacao ?? "";
        $("#cOcupacao").value = c.ocupacao ?? "TITULAR";
      });
      tbody.appendChild(tr);
    });
  }

  $("#cCpf")?.addEventListener("input", fillCtpsSerieFromCpf);
  $("#cPostoNome")?.addEventListener("change", buildColabIdPosto);
  $("#cNrPosto")?.addEventListener("input", buildColabIdPosto);

  document.querySelector('[data-view="colaboradores"]')?.addEventListener("click", async () => {
    await loadLotacoesIntoSelect();
    await listColaboradores();
  });

  $("#btnSalvarColab")?.addEventListener("click", async () => {
    const matricula = ($("#cMatricula").value || "").trim();
    const nome = ($("#cNome").value || "").trim();
    const cpf = cpfNormalize($("#cCpf").value || "");
    const sexo = $("#cSexo").value || "M";
    const profissao = $("#cProfissao").value || "";
    const postoNome = $("#cPostoNome").value || "";
    const nrPosto = Number($("#cNrPosto").value || "");
    const idPosto = buildColabIdPosto();
    const lotacao = $("#cLotacao").value || "";
    const admissao = $("#cAdmissao").value || null;
    const ocupacao = $("#cOcupacao").value || "TITULAR";

    fillCtpsSerieFromCpf();
    const ctps = $("#cCtps").value || null;
    const serie = $("#cSerie").value || null;

    if (matricula.length !== 4) return alert("Matrícula deve ter 4 caracteres.");
    if (!nome) return alert("Informe o nome.");
    if (cpf.length !== 11) return alert("CPF inválido.");
    if (!profissao) return alert("Selecione a profissão.");
    if (!postoNome) return alert("Selecione o posto (nome).");
    if (!nrPosto || nrPosto < 1) return alert("Informe o Nr Posto.");
    if (!idPosto) return alert("ID.Posto não foi gerado.");
    if (!lotacao) return alert("Selecione a lotação.");
    if (!admissao) return alert("Informe a admissão.");

    const payload = {
      p_nome: nome,
      p_sexo: sexo,
      p_cpf: cpf,
      p_profissao: profissao,
      p_data_admissao: admissao,
      p_ctps: ctps,
      p_serie_ctps: serie,
      p_ocupacao: ocupacao,
      p_matricula: matricula,
      p_posto_nome: postoNome,
      p_nr_posto: nrPosto,
      p_id_posto_ref: idPosto,
      p_lotacao: lotacao
    };

    const { error } = await window.supabase.rpc("insert_colaborador", payload);
    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    showMsg("#msgColab", "Salvo com sucesso.");
    await listColaboradores();       // atualiza e mostra o último cadastro
    clearColabForm();

  });

  $("#btnBuscarColabPorCpf")?.addEventListener("click", async () => {
    const cpf = cpfNormalize($("#cCpf").value || "");
    if (cpf.length !== 11) return alert("CPF inválido.");

    const { data, error } = await window.supabase.rpc("find_colaborador_by_cpf", { p_cpf: cpf });
    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    const c = data?.[0];
    if (!c) return alert("Não encontrado.");

    $("#cNome").value = c.nome || "";
    $("#cSexo").value = c.sexo || "M";
    $("#cProfissao").value = c.profissao || "";
    $("#cAdmissao").value = c.data_admissao || "";
    $("#cOcupacao").value = (c.ocupacao === "VOLANTE" ? "VOLANTE" : "TITULAR");
    fillCtpsSerieFromCpf();
  });

  $("#btnListarColab")?.addEventListener("click", listColaboradores);

  $("#btnAlterarColab")?.addEventListener("click", async () => {
    const id = $("#cId").value || "";
    if (!id) return alert("Selecione um registro na lista para alterar.");

    const matricula = ($("#cMatricula").value || "").trim();
    const nome = ($("#cNome").value || "").trim();
    const sexo = $("#cSexo").value || "M";
    const profissao = $("#cProfissao").value || "";
    const postoNome = $("#cPostoNome").value || "";
    const nrPosto = Number($("#cNrPosto").value || "");
    const idPosto = buildColabIdPosto();
    const lotacao = $("#cLotacao").value || "";
    const admissao = $("#cAdmissao").value || null;
    const ocupacao = $("#cOcupacao").value || "TITULAR";

    if (matricula.length !== 4) return alert("Matrícula deve ter 4 caracteres.");
    if (!nome) return alert("Informe o nome.");
    if (!profissao) return alert("Selecione a profissão.");
    if (!postoNome) return alert("Selecione o posto (nome).");
    if (!nrPosto || nrPosto < 1) return alert("Informe o Nr Posto.");
    if (!idPosto) return alert("ID.Posto não foi gerado.");
    if (!lotacao) return alert("Selecione a lotação.");
    if (!admissao) return alert("Informe a admissão.");

    const { error } = await window.supabase
      .from("colaboradores")
      .update({
        matricula, nome, sexo, profissao,
        posto_nome: postoNome,
        nr_posto: nrPosto,
        id_posto_ref: idPosto,
        lotacao,
        data_admissao: admissao,
        ocupacao
      })
      .eq("id", id);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    alert("Alterado com sucesso.");
    await listColaboradores();
  });

  $("#btnExcluirColab")?.addEventListener("click", async () => {
    const id = $("#cId").value || "";
    if (!id) return alert("Selecione um registro na lista para excluir.");
    if (!confirm("Confirma excluir este colaborador?")) return;

    const { error } = await window.supabase
      .from("colaboradores")
      .update({ ativo: false })
      .eq("id", id);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    alert("Excluído com sucesso.");
    await listColaboradores();
    clearColabForm();
  });

  // =========================
  // POSTOS
  // =========================
  function genIdPostoPreview() {
    const posto = ($("#pNome").value || "").trim().replace(/\s+/g, "-").toUpperCase();
    const nro = ($("#pNumero").value || "").trim();
    const seq = ($("#pSeq").value || "1").trim();
    const contrato = ($("#pContrato").value || "").trim();
    const ano = ($("#pAno").value || "").trim();
    $("#pIdPosto").value = posto && nro && seq && contrato && ano ? `${posto}-${nro}-${seq}-${contrato}-${ano}` : "";
  }
  ["#pNome", "#pNumero", "#pSeq", "#pContrato", "#pAno"].forEach((id) => $(id)?.addEventListener("input", genIdPostoPreview));

  async function listPostos() {
    const { data, error } = await window.supabase
      .from("postos")
      .select("id, id_posto, posto_nome, turno, lotacao_macro, lotacao, cidade, status, nro_posto, sequencial, contrato, ano, descritivo_lotacao")
      .order("id_posto", { ascending: true })
      .limit(300);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    const tbody = $("#tblPostos tbody");
    tbody.innerHTML = "";

    (data || []).forEach((p) => {
      const tr = document.createElement("tr");
      tr.style.cursor = "pointer";
      tr.innerHTML = `
        <td>${p.id_posto || ""}</td>
        <td>${p.posto_nome || ""}</td>
        <td>${p.turno || ""}</td>
        <td>${p.lotacao_macro || ""}</td>
        <td>${p.lotacao || ""}</td>
        <td>${p.cidade || ""}</td>
        <td>${p.status || ""}</td>
      `;
      tr.addEventListener("click", () => {
        $("#pIdInterno").value = p.id || "";
        $("#pNome").value = p.posto_nome || "";
        $("#pNumero").value = p.nro_posto ?? "";
        $("#pSeq").value = p.sequencial ?? 1;
        $("#pContrato").value = p.contrato ?? "2";
        $("#pAno").value = p.ano ?? 2023;
        $("#pTurno").value = p.turno || "Matutino";
        $("#pStatus").value = p.status || "VAGO";
        $("#pMacro").value = p.lotacao_macro || "";
        $("#pLotacao").value = p.lotacao || "";
        $("#pDesc").value = p.descritivo_lotacao || "";
        $("#pCidade").value = p.cidade || "";
        $("#pIdPosto").value = p.id_posto || "";
      });
      tbody.appendChild(tr);
    });
  }

  $("#btnSalvarPostoRPC")?.addEventListener("click", async () => {
    const payload = {
      p_posto_nome: $("#pNome").value.trim(),
      p_nro_posto: Number($("#pNumero").value),
      p_sequencial: Number($("#pSeq").value || 1),
      p_contrato: $("#pContrato").value.trim(),
      p_ano: Number($("#pAno").value),
      p_turno: $("#pTurno").value,
      p_lotacao_macro: $("#pMacro").value.trim() || null,
      p_lotacao: $("#pLotacao").value.trim() || null,
      p_descritivo_lotacao: $("#pDesc").value.trim() || null,
      p_cidade: $("#pCidade").value.trim() || null,
      p_status: $("#pStatus").value,
    };

    const { data, error } = await window.supabase.rpc("upsert_posto", payload);
    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    $("#pIdPosto").value = data?.id_posto || $("#pIdPosto").value;
    showMsg("#msgPostos", "Salvo com sucesso.", 8000);
    await listPostos();
  });

  $("#btnAlterarPosto")?.addEventListener("click", () => $("#btnSalvarPostoRPC")?.click());

  $("#btnExcluirPosto")?.addEventListener("click", async () => {
    const idInterno = $("#pIdInterno").value;
    if (!idInterno) return alert("Selecione um posto na lista para excluir.");
    if (!confirm("Confirma excluir este posto?")) return;

    const { error } = await window.supabase
      .from("postos")
      .update({ status: "VAGO" })
      .eq("id", idInterno);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    alert("Excluído (marcado como VAGO).");
    await listPostos();
  });

  $("#btnListarPostos")?.addEventListener("click", listPostos);
  document.querySelector('[data-view="postos"]')?.addEventListener("click", listPostos);

  // =========================
  // OCORRÊNCIAS
  // =========================
  function calcTotalDias(ini, fim) {
    if (!ini || !fim) return "";
    const d1 = new Date(ini);
    const d2 = new Date(fim);
    if (Number.isNaN(d1.getTime()) || Number.isNaN(d2.getTime())) return "";
    const diff = Math.floor((d2 - d1) / (1000 * 60 * 60 * 24));
    return diff >= 0 ? (diff + 1).toString() : "";
  }

  async function preencherNomePorMatricula() {
    const matricula = ($("#oMatricula").value || "").trim();
    $("#oNome").value = "";
    $("#oId").dataset.colabId = "";

    if (matricula.length !== 4) return;

    const { data, error } = await window.supabase.rpc("find_colaborador_by_matricula", { p_matricula: matricula });
    if (error) return console.warn(error);

    if (data && data.length) {
      $("#oNome").value = data[0].nome || "";
      $("#oId").dataset.colabId = data[0].id;
    }
  }

  $("#oMatricula")?.addEventListener("input", preencherNomePorMatricula);
  $("#oIni")?.addEventListener("change", () => $("#oTotalDias").value = calcTotalDias($("#oIni").value, $("#oFim").value));
  $("#oFim")?.addEventListener("change", () => $("#oTotalDias").value = calcTotalDias($("#oIni").value, $("#oFim").value));

  async function listOcorrencias() {
    const { data, error } = await window.supabase
      .from("ocorrencias")
      .select("numero, colaborador_id, posto_id, motivo, data_inicio, data_fim, total_dias, tipo_substituicao, substituto")
      .order("numero", { ascending: false })
      .limit(300);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    const ids = [...new Set((data || []).map(o => o.colaborador_id).filter(Boolean))];
    let colabMap = new Map();

    if (ids.length) {
      const { data: cols } = await window.supabase
        .from("colaboradores")
        .select("id, matricula, nome")
        .in("id", ids);

      (cols || []).forEach(c => colabMap.set(c.id, { matricula: c.matricula || "", nome: c.nome || "" }));
    }

    const tbody = $("#tblOcorrencias tbody");
    tbody.innerHTML = "";

    (data || []).forEach(o => {
      const c = colabMap.get(o.colaborador_id) || { matricula: "", nome: "" };
      const periodo = `${o.data_inicio || ""} a ${o.data_fim || ""}`;

      tbody.insertAdjacentHTML("beforeend", `
        <tr>
          <td>${o.numero ?? ""}</td>
          <td>${c.matricula}</td>
          <td>${c.nome}</td>
          <td>${o.posto_id ?? ""}</td>
          <td>${o.motivo ?? ""}</td>
          <td>${periodo}</td>
          <td>${o.total_dias ?? ""}</td>
          <td>${o.tipo_substituicao ?? ""}</td>
          <td>${o.substituto ?? ""}</td>
        </tr>
      `);
    });
  }

  $("#btnListarOcorrencias")?.addEventListener("click", listOcorrencias);

  $("#btnSalvarOcorrenciaRPC")?.addEventListener("click", async () => {
    const matricula = ($("#oMatricula").value || "").trim();
    const nome = ($("#oNome").value || "").trim();
    const colabId = $("#oId").dataset.colabId || "";
    const idPosto = ($("#oIdPostoText").value || "").trim();
    const tipoSub = ($("#oTipoSub").value || "").trim();
    const ini = $("#oIni").value;
    const fim = $("#oFim").value;
    const motivo = $("#oMotivo").value;
    const substituto = ($("#oSubstituto").value || "").trim();

    $("#oTotalDias").value = calcTotalDias(ini, fim);

    if (matricula.length !== 4) return alert("Informe a matrícula (4 caracteres).");
    if (!colabId) return alert("Matrícula não encontrada. Cadastre o colaborador antes.");
    if (!nome) return alert("Nome não localizado para a matrícula informada.");
    if (!idPosto) return alert("Informe o ID.Posto.");
    if (!tipoSub) return alert("Selecione o tipo de substituição.");
    if (!ini || !fim) return alert("Informe início e fim.");
    if (!$("#oTotalDias").value) return alert("Período inválido (fim menor que início).");

    const { error } = await window.supabase
      .from("ocorrencias")
      .insert([{
        colaborador_id: colabId,
        posto_id: idPosto,
        motivo,
        data_inicio: ini,
        data_fim: fim,
        tipo_substituicao: tipoSub,
        substituto: substituto || null
      }]);

    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    alert("Salvo com sucesso.");
    await listOcorrencias();

    $("#oMatricula").value = "";
    $("#oNome").value = "";
    $("#oIdPostoText").value = "";
    $("#oTipoSub").value = "";
    $("#oIni").value = "";
    $("#oFim").value = "";
    $("#oTotalDias").value = "";
    $("#oMotivo").value = "Outros";
    $("#oSubstituto").value = "";
    $("#oId").dataset.colabId = "";
  });

  document.querySelector('[data-view="ocorrencias"]')?.addEventListener("click", async () => {
    $("#oTotalDias").value = calcTotalDias($("#oIni").value, $("#oFim").value);
    await listOcorrencias();
  });

  // =========================
  // IMPORTAÇÃO: Templates CSV
  // =========================
  function downloadTextFile(filename, content, mime = "text/csv;charset=utf-8") {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }
  function makeCsvTemplate(headers) {
    const headerLine = headers.join(";");
    const exampleLine = headers.map(() => "").join(";");
    return `${headerLine}\n${exampleLine}\n`;
  }
  const TEMPLATE_COLAB = ["matricula(4)","nome","cpf(11)","sexo(M/F)","profissao","posto_nome","nr_posto","lotacao","data_admissao(YYYY-MM-DD)","ocupacao(TITULAR/VOLANTE)"];
  const TEMPLATE_POSTOS = ["posto_nome","nro_posto","sequencial","contrato","ano","turno","lotacao_macro(Tribunal/Comarca)","lotacao","descritivo_lotacao","cidade","status(VAGO/PREENCHIDO)"];
  const TEMPLATE_OCORR = ["matricula(4)","id_posto","motivo","data_inicio(YYYY-MM-DD)","data_fim(YYYY-MM-DD)","tipo_substituicao(Tipo 1/Tipo 2/Tipo 3)","substituto"];

  $("#btnTplColab")?.addEventListener("click", () => downloadTextFile("template_colaboradores.csv", makeCsvTemplate(TEMPLATE_COLAB)));
  $("#btnTplPostos")?.addEventListener("click", () => downloadTextFile("template_postos.csv", makeCsvTemplate(TEMPLATE_POSTOS)));
  $("#btnTplOcorr")?.addEventListener("click", () => downloadTextFile("template_ocorrencias.csv", makeCsvTemplate(TEMPLATE_OCORR)));

  // Botões Importar/Exportar (mantidos como placeholders, se você já tinha lógica, ela pode ficar aqui)
 async function importPostosFromRows(rows) {
  let ok = 0, fail = 0;
  for (const r of rows) {
    try {
      // aceita várias grafias do cabeçalho
      const posto_nome = (r["posto_nome"] || r["Posto"] || r["posto"] || "").toString().trim();
      const nro_posto = Number(r["nro_posto"] || r["Nº Posto"] || r["nro"] || r["numero"] || "");
      const sequencial = Number(r["sequencial"] || r["Sequencial"] || 1);
      const contrato = (r["contrato"] || r["Contrato"] || "2").toString().trim();
      const ano = Number(r["ano"] || r["Ano"] || 2023);
      const turno = (r["turno"] || r["Turno"] || "Matutino").toString().trim();
      const lotacao_macro = (r["lotacao_macro"] || r["Lotação Macro"] || r["macro"] || "").toString().trim() || null;
      const lotacao = (r["lotacao"] || r["Lotação"] || "").toString().trim() || null;
      const descritivo_lotacao = (r["descritivo_lotacao"] || r["Descritivo"] || "").toString().trim() || null;
      const cidade = (r["cidade"] || r["Cidade"] || "").toString().trim() || null;
      const status = (r["status"] || r["Status"] || "VAGO").toString().trim();

      if (!posto_nome || !nro_posto) { fail++; continue; }

      const payload = {
        p_posto_nome: posto_nome,
        p_nro_posto: nro_posto,
        p_sequencial: sequencial,
        p_contrato: contrato,
        p_ano: ano,
        p_turno: turno,
        p_lotacao_macro: lotacao_macro,
        p_lotacao: lotacao,
        p_descritivo_lotacao: descritivo_lotacao,
        p_cidade: cidade,
        p_status: status
      };

      const { error } = await window.supabase.rpc("upsert_posto", payload);
      if (error) { fail++; continue; }

      ok++;
    } catch {
      fail++;
    }
  }
  return { ok, fail };
}

function parseCsvSemicolon(text) {
  const lines = text.split(/\r?\n/).filter(l => l.trim().length);
  if (!lines.length) return [];
  const headers = lines[0].split(";").map(h => h.trim());
  const out = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(";");
    const row = {};
    headers.forEach((h, idx) => row[h] = (cols[idx] ?? "").trim());
    out.push(row);
  }
  return out;
}

async function readFileAsText(file) {
  return new Promise((res, rej) => {
    const fr = new FileReader();
    fr.onload = () => res(fr.result);
    fr.onerror = rej;
    fr.readAsText(file, "utf-8");
  });
}

async function readExcelRows(file) {
  return new Promise((res, rej) => {
    const fr = new FileReader();
    fr.onload = () => {
      const data = new Uint8Array(fr.result);
      const wb = XLSX.read(data, { type: "array" });
      const ws = wb.Sheets[wb.SheetNames[0]];
      const rows = XLSX.utils.sheet_to_json(ws, { defval: "" });
      res(rows);
    };
    fr.onerror = rej;
    fr.readAsArrayBuffer(file);
  });
}

document.querySelector("#btnImportar")?.addEventListener("click", async () => {
  const file = document.querySelector("#fileImport")?.files?.[0];
  if (!file) return alert("Selecione um arquivo (CSV/Excel).");

  // você pode decidir aqui: se quiser importar só postos, ok.
  // se quiser escolher módulo, eu adiciono um select no HTML.
  try {
    let rows = [];
    if (file.name.toLowerCase().endsWith(".csv")) {
      const txt = await readFileAsText(file);
      rows = parseCsvSemicolon(txt);
    } else {
      rows = await readExcelRows(file);
    }

    if (!rows.length) return alert("Arquivo sem dados.");

    // Importa como POSTOS
    const result = await importPostosFromRows(rows);
    alert(`Importação concluída. OK: ${result.ok} | Falhas: ${result.fail}`);

    // Atualiza a lista do módulo Postos se você estiver nele
    if (typeof listPostos === "function") await listPostos();
  } catch (e) {
    alert("Erro ao importar: " + (e?.message || e));
  }
});

  // =========================
  // RELATÓRIOS (filtro por matrícula/lotação/período)
  // =========================
  function setRelatorioFiltroUI(tipo) {
    $("#wrap-rMatricula").style.display = (tipo === "matricula") ? "" : "none";
    $("#wrap-rLotacao").style.display = (tipo === "lotacao") ? "" : "none";
    $("#wrap-rIni").style.display = (tipo === "periodo") ? "" : "none";
    $("#wrap-rFim").style.display = (tipo === "periodo") ? "" : "none";
  }
  $("#rFiltroTipo")?.addEventListener("change", (e) => setRelatorioFiltroUI(e.target.value));
  document.querySelector('[data-view="relatorios"]')?.addEventListener("click", () => setRelatorioFiltroUI($("#rFiltroTipo").value || "matricula"));

  async function fetchColabMapByIds(ids) {
    if (!ids.length) return new Map();
    const { data, error } = await window.supabase
      .from("colaboradores")
      .select("id, matricula, nome, lotacao")
      .in("id", ids);
    if (error) { console.warn(error); return new Map(); }

    const m = new Map();
    (data || []).forEach(c => m.set(c.id, { matricula: c.matricula || "", nome: c.nome || "", lotacao: c.lotacao || "" }));
    return m;
  }

  async function gerarRelatorio() {
    const tipo = $("#rFiltroTipo")?.value || "matricula";
    const valMat = ($("#rMatricula")?.value || "").trim();
    const valLot = ($("#rLotacao")?.value || "").trim();
    const ini = $("#rIni")?.value || "";
    const fim = $("#rFim")?.value || "";

    let q = window.supabase
      .from("ocorrencias")
      .select("numero, colaborador_id, posto_id, motivo, data_inicio, data_fim, total_dias, tipo_substituicao, substituto")
      .order("numero", { ascending: false })
      .limit(500);

    if (tipo === "periodo") {
      if (!ini || !fim) return alert("Informe Início e Fim do período.");
      q = q.gte("data_inicio", ini).lte("data_inicio", fim);
    }

    const { data: ocorrs, error } = await q;
    if (error) { showMsg('#msgPostos', 'Erro ao listar: ' + error.message, 12000); return; }

    const ids = [...new Set((ocorrs || []).map(o => o.colaborador_id).filter(Boolean))];
    const colabMap = await fetchColabMapByIds(ids);

    let filtrado = ocorrs || [];

    if (tipo === "matricula") {
      if (valMat.length !== 4) return alert("Informe a matrícula (4 caracteres).");
      filtrado = filtrado.filter(o => (colabMap.get(o.colaborador_id)?.matricula || "") === valMat);
    }

    if (tipo === "lotacao") {
      if (!valLot) return alert("Informe a lotação.");
      const alvo = valLot.toLowerCase();
      filtrado = filtrado.filter(o => (colabMap.get(o.colaborador_id)?.lotacao || "").toLowerCase().includes(alvo));
    }

    const tbody = $("#tblRelatorio tbody");
    tbody.innerHTML = "";

    filtrado.forEach(o => {
      const c = colabMap.get(o.colaborador_id) || { matricula: "", nome: "", lotacao: "" };
      const periodo = `${o.data_inicio || ""} a ${o.data_fim || ""}`;

      tbody.insertAdjacentHTML("beforeend", `
        <tr>
          <td>${o.numero ?? ""}</td>
          <td>${c.matricula}</td>
          <td>${c.nome}</td>
          <td>${c.lotacao}</td>
          <td>${o.posto_id ?? ""}</td>
          <td>${o.motivo ?? ""}</td>
          <td>${periodo}</td>
          <td>${o.total_dias ?? ""}</td>
          <td>${o.tipo_substituicao ?? ""}</td>
          <td>${o.substituto ?? ""}</td>
        </tr>
      `);
    });

    if (!filtrado.length) alert("Nenhum registro encontrado para o filtro informado.");
  }

  $("#btnGerarRelatorio")?.addEventListener("click", gerarRelatorio);

  // =========================
  // BOOT
  // =========================
  (async function init() {
    showView("dashboard");
    const logged = await refreshAuthUI();
    if (logged) await loadDashboard();
  })();
})();