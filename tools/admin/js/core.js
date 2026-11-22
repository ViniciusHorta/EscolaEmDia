// Núcleo partilhado: estado, chamadas ao Supabase, mensagens e diálogos.
window.A = window.A || {};
(() => {
  'use strict';
  const A = window.A;

  A.$ = (id) => document.getElementById(id);
  A.esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // Normaliza para pesquisa: minúsculas e sem acentos.
  A.norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

  A.state = { url: '', key: '', subjects: [], topics: [], worksheets: [], reports: [], contents: [], contentsMissing: false };

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
    CONTENT_EXISTS: 'Já existe um conteúdo com esse nome neste tema.',
    CONTENT_NOT_FOUND: 'O conteúdo não existe.',
    CONTENT_IN_USE: 'O conteúdo tem fichas ligadas: só pode mudar para um tema da mesma disciplina e ano.',
    CONTENT_MISMATCH: 'Os conteúdos escolhidos têm de ser da disciplina e do ano da ficha.',
    INVALID_SEMESTER: 'Semestre inválido (1.º, 2.º ou nenhum).',
    INVALID_ITEMS: 'Lista vazia ou demasiado longa (máx. 2000 conteúdos).',
    REPORT_NOT_FOUND: 'O relato não existe.',
    FREE_WORKSHEET_TOO_MANY_QUESTIONS: 'Fichas Free não podem ter mais perguntas do que o limite do plano gratuito. Reduz as perguntas ou muda a ficha para Premium.',
    INVALID_TIER: 'Tipo de acesso inválido (Free ou Premium).',
    CHILD_NOT_FOUND: 'A criança não existe.',
    INVALID_DAYS: 'Número de dias inválido (1 a 3650).',
    NO_MANUAL_SUBSCRIPTION: 'A criança não tem Premium manual ativo. Assinaturas pagas gerem-se na plataforma de origem.',
    CHILD_ALREADY_PREMIUM: 'A criança já tem uma assinatura Premium ativa.',
    SETTING_NOT_FOUND: 'Limite desconhecido.',
    SETTING_OUT_OF_RANGE: 'Valor fora das margens permitidas.',
    SUBSCRIPTION_NOT_FOUND: 'A assinatura não existe.',
    SUBSCRIPTION_NOT_ACTIVE: 'A assinatura já não está ativa.',
    ALREADY_NOT_RENEWING: 'A assinatura já está cancelada (não renova).',
    CHANNEL_NOT_SUPPORTED: 'Esta forma de pagamento não pode ser cancelada daqui.',
    PAYMENTS_UNAVAILABLE: 'O servidor não tem as credenciais desta plataforma de pagamento.',
    UNAUTHORIZED: 'Chave sem permissão para esta ação. Usa a chave service_role legacy (JWT).',
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
      // Erros lançados pela base (raise exception) com código conhecido.
      if (body && A.errorText[body.message]) {
        throw new ApiError(body.message, A.errorText[body.message] + (body.details ? ' ' + body.details : ''));
      }
      throw new ApiError('HTTP', (body && (body.message || body.hint)) || `HTTP ${res.status}: ${text.slice(0, 200)}`);
    }
    if (body && typeof body === 'object' && !Array.isArray(body) && body.error) throw new ApiError(body.error);
    return body;
  };

  // Edge Functions de administração (ex.: admin-billing). Autorização: a mesma chave service_role.
  A.fn = async (path, body) => {
    let res;
    try {
      res = await fetch(`${A.state.url}/functions/v1/${path}`, { method: 'POST', headers: headers(), body: JSON.stringify(body ?? {}) });
    } catch (e) {
      throw new ApiError('NETWORK', 'Sem ligação ao Supabase (' + e.message + ').');
    }
    const data = await res.json().catch(() => null);
    if (res.status === 404 && !data?.error) throw new ApiError('HTTP', 'A Edge Function não existe neste projeto. Faz o deploy de admin-billing.');
    if (!res.ok || data?.error) {
      const code = data?.error || 'HTTP';
      throw new ApiError(code, (A.errorText[code] || `Erro ${res.status}`) + (data?.message ? ' — ' + data.message : ''));
    }
    return data;
  };

  // ---------- Imagens das questões (Storage, bucket público question-images) ----------
  A.IMAGE_BUCKET = 'question-images';
  A.IMAGE_MAX_BYTES = 2 * 1024 * 1024; // igual ao file_size_limit do bucket
  A.IMAGE_TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' };
  A.imageUrl = (path) => `${A.state.url}/storage/v1/object/public/${A.IMAGE_BUCKET}/${String(path).split('/').map(encodeURIComponent).join('/')}`;

  // Reduz fotos grandes (lado maior até 1600 px, WebP). GIF fica como está para não perder a animação.
  async function shrinkImage(file) {
    if (file.type === 'image/gif') return file;
    const bmp = await createImageBitmap(file);
    const scale = Math.min(1, 1600 / Math.max(bmp.width, bmp.height));
    if (scale === 1 && file.size <= A.IMAGE_MAX_BYTES) { bmp.close(); return file; }
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bmp.width * scale); canvas.height = Math.round(bmp.height * scale);
    canvas.getContext('2d').drawImage(bmp, 0, 0, canvas.width, canvas.height);
    bmp.close();
    const blob = await new Promise((ok) => canvas.toBlob(ok, 'image/webp', 0.85));
    return blob || file;
  }

  // Envia uma imagem e devolve o caminho no bucket (ex.: "3f2a….webp").
  // Os ficheiros nunca se apagam daqui: versões publicadas antigas podem continuar a usá-los.
  A.uploadImage = async (file) => {
    if (!A.IMAGE_TYPES[file.type]) throw new ApiError('IMAGE_TYPE', 'Formato não suportado. Usa PNG, JPEG, WebP ou GIF.');
    let blob;
    try { blob = await shrinkImage(file); } catch { blob = file; }
    if (blob.size > A.IMAGE_MAX_BYTES) throw new ApiError('IMAGE_SIZE', `A imagem tem ${(blob.size / 1048576).toFixed(1)} MB; o máximo é 2 MB.`);
    const type = blob.type || file.type;
    const path = `${crypto.randomUUID()}.${A.IMAGE_TYPES[type] || 'png'}`;
    let res;
    try {
      res = await fetch(`${A.state.url}/storage/v1/object/${A.IMAGE_BUCKET}/${path}`, {
        method: 'POST', headers: { ...headers(), 'Content-Type': type, 'Cache-Control': '31536000', 'x-upsert': 'false' }, body: blob,
      });
    } catch (e) {
      throw new ApiError('NETWORK', 'Sem ligação ao Supabase (' + e.message + ').');
    }
    if (!res.ok) {
      const body = await res.json().catch(() => null);
      if (res.status === 404 || /bucket not found/i.test(body?.message || '')) throw new ApiError('HTTP', 'O bucket question-images não existe. Aplica a migração 202611220001_question_images_bucket.sql.');
      throw new ApiError('HTTP', 'Falha ao enviar a imagem: ' + (body?.message || body?.error || `HTTP ${res.status}`));
    }
    return path;
  };

  A.loadCatalogue = async () => {
    const o = await A.rpc('admin_catalogue_overview');
    A.state.subjects = o.subjects || [];
    A.state.topics = o.topics || [];
  };
  // Conteúdos da grade (só admin). Sem a migração 202611210001, o resto do admin continua a funcionar.
  A.loadContents = async () => {
    try { A.state.contents = (await A.rpc('admin_list_contents')) || []; A.state.contentsMissing = false; }
    catch (e) { if (e.code !== 'MIGRATION_MISSING') throw e; A.state.contents = []; A.state.contentsMissing = true; }
  };
  A.contentsFor = (topicId) => A.state.contents.filter((c) => c.topicId === topicId)
    .sort((a, b) => a.position - b.position || a.name.localeCompare(b.name, 'pt'));
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
  A.dialog = ({ title, body, ok = 'Guardar', cancel = 'Cancelar', danger = false, info = false, onSubmit }) => new Promise((resolve) => {
    const dlg = A.$('dlg'), form = A.$('dlgForm'), okBtn = A.$('dlgOk');
    A.$('dlgTitle').textContent = title;
    A.$('dlgBody').innerHTML = body;
    A.$('dlgErr').innerHTML = '';
    okBtn.textContent = ok;
    okBtn.className = danger ? 'danger' : '';
    A.$('dlgCancel').textContent = cancel;
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
