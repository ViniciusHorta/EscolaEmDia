// Núcleo partilhado: estado, chamadas ao Supabase, mensagens e diálogos.
window.A = window.A || {};
(() => {
  'use strict';
  const A = window.A;

  A.$ = (id) => document.getElementById(id);
  A.esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // Normaliza para pesquisa: minúsculas e sem acentos.
  A.norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

  A.state = { url: '', key: '', subjects: [], topics: [], worksheets: [], reports: [] };

  // ---------- Erros ----------
  A.errorText = {
    INVALID_NAME: 'Nome inválido (não pode ficar vazio nem ser demasiado longo).',
    SUBJECT_EXISTS: 'Já existe uma disciplina com esse nome.',
    SUBJECT_NOT_FOUND: 'A disciplina não existe.',
    SUBJECT_IN_USE: 'A disciplina tem temas ou fichas; apaga-os ou move-os primeiro.',
    SUBJECT_LOCKED: 'A disciplina de uma ficha já publicada não pode ser alterada. Cria uma nova ficha.',
    TOPIC_EXISTS: 'Já existe um tema com esse nome nesta disciplina e ano (pode estar arquivado — vê o filtro «Arquivados»).',
    TOPIC_ARCHIVED: 'Um dos temas escolhidos está arquivado. Reativa-o na área Temas ou escolhe outro.',
    TOPIC_IN_CURRENT_USE: 'O tema ainda é usado pela versão atual (ou pela versão publicada) de alguma ficha. Retira-o dessas fichas e publica-as antes de o arquivar.',
    TOPIC_NOT_FOUND: 'O tema não existe.',
    TOPIC_IN_USE: 'O tema é usado por fichas: só pode ser renomeado (não muda de disciplina/ano nem pode ser apagado).',
    TOPIC_MISMATCH: 'Os temas escolhidos têm de pertencer à disciplina e ao ano da ficha.',
    TOPICS_REQUIRED: 'Escolhe pelo menos um tema.',
    INVALID_SCHOOL_YEAR: 'Ano escolar inválido (1 a 4).',
    INVALID_TITLE: 'Título inválido (1 a 160 caracteres).',
    INVALID_CONTENT: 'A base rejeitou o conteúdo da ficha (regras de validação).',
    WORKSHEET_NOT_FOUND: 'A ficha não existe.',
    WORKSHEET_PUBLISHED: 'Fichas já publicadas não podem ser apagadas (podem ter atribuições e respostas). Arquiva-a.',
    NO_PUBLISHED_VERSION: 'A ficha ainda não tem nenhuma versão publicada. Abre-a e usa «Guardar e publicar».',
    INVALID_STATUS: 'Estado inválido.',
    REPORT_NOT_FOUND: 'O relato não existe.',
    MIGRATION_MISSING: 'As funções de administração não existem na base. Aplica a migração 202611060001_admin_catalogue_management.sql.',
  };
  class ApiError extends Error {
    constructor(code, message) { super(message || A.errorText[code] || code); this.code = code; }
  }
  A.ApiError = ApiError;

  // ---------- Supabase ----------
  function headers() {
    const h = { apikey: A.state.key, 'Content-Type': 'application/json' };
    if (A.state.key.startsWith('eyJ')) h.Authorization = 'Bearer ' + A.state.key; // chave legacy (JWT)
    return h;
  }

  A.rpc = async (name, args = {}) => {
    let res;
    try {
      res = await fetch(`${A.state.url}/rest/v1/rpc/${name}`, { method: 'POST', headers: headers(), body: JSON.stringify(args) });
    } catch (e) {
      throw new ApiError('NETWORK', 'Sem ligação ao Supabase (' + e.message + ').');
    }
    const text = await res.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch { /* resposta não-JSON */ }
    if (!res.ok) {
      if (body && (body.code === 'PGRST202' || body.code === '42883')) throw new ApiError('MIGRATION_MISSING');
      if (res.status === 401 || res.status === 403) throw new ApiError('AUTH', 'Chave sem permissão. Usa a chave service_role legacy (JWT).');
      throw new ApiError('HTTP', (body && (body.message || body.hint)) || `HTTP ${res.status}: ${text.slice(0, 200)}`);
    }
    if (body && typeof body === 'object' && !Array.isArray(body) && body.error) throw new ApiError(body.error);
    return body;
  };

  A.loadCatalogue = async () => {
    const o = await A.rpc('admin_catalogue_overview');
    A.state.subjects = o.subjects || [];
    A.state.topics = o.topics || [];
  };
  A.loadWorksheets = async () => { A.state.worksheets = (await A.rpc('admin_list_worksheets')) || []; };

  // ---------- Consultas ao estado ----------
  A.subject = (id) => A.state.subjects.find((s) => s.id === id);
  A.topic = (id) => A.state.topics.find((t) => t.id === id);
  // Por omissão exclui temas arquivados; «keep» mantém os ids indicados mesmo que arquivados.
  A.topicsFor = (subjectId, year, keep = null) => A.state.topics
    .filter((t) => t.subjectId === subjectId && t.schoolYear === Number(year) && (!t.archivedAt || (keep && keep.has(t.id))))
    .sort((a, b) => a.name.localeCompare(b.name, 'pt'));
  A.subjectOptions = (selected, allLabel) =>
    (allLabel ? `<option value="">${A.esc(allLabel)}</option>` : '') +
    A.state.subjects.map((s) => `<option value="${s.id}" ${s.id === selected ? 'selected' : ''}>${A.esc(s.name)}</option>`).join('');
  // Anos escolares suportados, agrupados por ciclo do ensino básico.
  A.CYCLES = [{ label: '1.º Ciclo', years: [1, 2, 3, 4] }, { label: '2.º Ciclo', years: [5, 6] }, { label: '3.º Ciclo', years: [7, 8, 9] }];
  A.yearOptions = (selected, allLabel) =>
    (allLabel ? `<option value="">${A.esc(allLabel)}</option>` : '') +
    A.CYCLES.map((c) => `<optgroup label="${c.label}">` + c.years
      .map((y) => `<option value="${y}" ${Number(selected) === y ? 'selected' : ''}>${y}.º Ano</option>`).join('') + '</optgroup>').join('');

  A.fmtDate = (iso) => iso ? new Date(iso).toLocaleString('pt-PT', { dateStyle: 'short', timeStyle: 'short' }) : '—';

  // ---------- Mensagens ----------
  A.msg = (kind, html) => `<div class="msg ${kind}" role="status">${html}</div>`;
  A.toast = (kind, html, ms = 4200) => {
    const el = document.createElement('div');
    el.innerHTML = A.msg(kind, html);
    const node = el.firstChild, box = A.$('toasts');
    box.appendChild(node);
    while (box.children.length > 3) box.firstChild.remove();
    setTimeout(() => node.remove(), ms);
  };
  A.fail = (e) => A.toast('err', A.esc(e.message || String(e)), 7000);

  A.copy = async (text, button, label = 'Copiado ✓') => {
    try { await navigator.clipboard.writeText(text); }
    catch {
      const area = document.createElement('textarea');
      area.value = text; document.body.appendChild(area); area.select(); document.execCommand('copy'); area.remove();
    }
    if (button) { const old = button.textContent; button.textContent = label; setTimeout(() => (button.textContent = old), 1600); }
  };

  // ---------- Diálogo genérico ----------
  // onSubmit(form) pode lançar erro: a mensagem aparece e o diálogo mantém-se aberto.
  A.dialog = ({ title, body, ok = 'Guardar', danger = false, info = false, onSubmit }) => new Promise((resolve) => {
    const dlg = A.$('dlg'), form = A.$('dlgForm'), okBtn = A.$('dlgOk');
    A.$('dlgTitle').textContent = title;
    A.$('dlgBody').innerHTML = body;
    A.$('dlgErr').innerHTML = '';
    okBtn.textContent = ok;
    okBtn.className = danger ? 'danger' : '';
    A.$('dlgCancel').hidden = info; // diálogo só informativo: apenas «Fechar»
    const cleanup = (value) => { form.onsubmit = null; A.$('dlgCancel').onclick = null; dlg.onclose = null; if (dlg.open) dlg.close(); resolve(value); };
    form.onsubmit = async (ev) => {
      ev.preventDefault();
      okBtn.disabled = true;
      try { const value = onSubmit ? await onSubmit(form) : true; cleanup(value ?? true); }
      catch (e) { A.$('dlgErr').innerHTML = A.msg('err', A.esc(e.message)); }
      finally { okBtn.disabled = false; }
    };
    A.$('dlgCancel').onclick = () => cleanup(null);
    dlg.onclose = () => cleanup(null);
    dlg.showModal();
    const first = form.querySelector('#dlgBody input:not([disabled]), #dlgBody select:not([disabled]), #dlgBody textarea');
    if (first) first.focus();
  });
})();
