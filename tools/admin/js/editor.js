// Editor de fichas: dados gerais, temas, perguntas (escolha múltipla, verdadeiro/falso, aberta), IA, JSON e publicação.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const E = A.editor = {};
  let ed = null;

  const clone = (x) => JSON.parse(JSON.stringify(x));
  // JSON com chaves ordenadas: a base (jsonb) não preserva a ordem das chaves.
  const stable = (v) => Array.isArray(v) ? `[${v.map(stable).join(',')}]`
    : v && typeof v === 'object' ? `{${Object.keys(v).sort().map((k) => JSON.stringify(k) + ':' + stable(v[k])).join(',')}}`
    : JSON.stringify(v);
  const letter = (j) => String.fromCharCode(65 + j);

  E.isDirty = () => !!(ed && ed.dirty);

  // ---------- Abrir / fechar ----------
  E.open = async (id, opts = {}) => {
    if (ed && ed.dirty && !confirm('Há alterações por gravar nesta ficha. Descartar?')) return;
    A.app.showTab('worksheets');
    let data = null;
    if (id) {
      try { data = await A.rpc('admin_get_worksheet', { p_id: id }); }
      catch (e) { A.fail(e); return; }
      if (!data) { A.toast('err', 'Ficha não encontrada.'); return; }
    }
    const listItem = id ? A.state.worksheets.find((w) => w.id === id) : null;
    const latest = data && data.latest;
    ed = {
      id, data, listItem,
      title: data ? data.title : '',
      subjectId: data ? data.subjectId : ($('fSubject').value || A.state.subjects[0]?.id || ''),
      year: latest ? latest.schoolYear : (Number($('fYear').value) || 1),
      topicIds: new Set(latest ? latest.topicIds : ($('fTopic').value ? [$('fTopic').value] : [])),
      content: latest ? clone(latest.content) : { instructions: '', questions: [] },
      dirty: false,
      ui: { ai: !id, json: false, preview: false, text: !!(latest && latest.content.text) },
      focusQuestionId: opts.focusQuestionId || null,
    };
    if (!Array.isArray(ed.content.questions)) ed.content.questions = [];
    ed.original = stable(ed.content);
    ed.originalMeta = stable({ y: ed.year, t: [...ed.topicIds].sort() });
    render();
  };

  function close() {
    if (ed && ed.dirty && !confirm('Há alterações por gravar nesta ficha. Descartar?')) return;
    ed = null;
    A.worksheets.closeEditor();
  }

  const hasPublished = () => !!(ed.data && ed.data.versions.some((v) => v.publishedAt));
  const latestPublished = () => !!(ed.data && ed.data.latest && ed.data.latest.publishedAt);
  const contentChanged = () => stable(ed.content) !== ed.original
    || stable({ y: ed.year, t: [...ed.topicIds].sort() }) !== ed.originalMeta;

  // ---------- Render ----------
  function render() {
    const view = $('wsEditorView');
    $('wsListView').hidden = true;
    view.hidden = false;
    const d = ed.data, li = ed.listItem;
    const statusBadge = !d ? '<span class="badge">Nova</span>'
      : ({ published: '<span class="badge ok">Publicada</span>', draft: '<span class="badge warn">Rascunho</span>', archived: '<span class="badge grey">Arquivada</span>' })[d.status] || '';
    view.innerHTML = `
      <div class="page-head">
        <button class="ghost" data-act="back">← Fichas</button>
        <h2>${d ? 'Editar ficha' : 'Nova ficha'}</h2> ${statusBadge}
        ${d && d.isSample ? '<span class="badge grey">Exemplo</span>' : ''}
      </div>

      <section>
        <div class="editor-meta">
          <div class="field"><label for="edTitle">Título da ficha</label>
            <input id="edTitle" data-m="title" maxlength="160" value="${esc(ed.title)}" placeholder="Ex.: Frações — partes iguais"></div>
          <div class="field"><label for="edSubject">Disciplina</label>
            <select id="edSubject" data-m="subject" ${hasPublished() ? 'disabled title="A disciplina de uma ficha publicada não pode mudar"' : ''}>${A.subjectOptions(ed.subjectId)}</select></div>
          <div class="field"><label for="edYear">Ano escolar</label><select id="edYear" data-m="year">${A.yearOptions(ed.year)}</select></div>
        </div>
        <label>Temas</label>
        <div id="edTopics" class="topic-pick"></div>
        <div class="version-info hint" style="margin:12px 0 0">${versionInfo(d, li)}</div>
      </section>

      <section>
        <div class="field"><label for="edInstructions">Instruções para a criança <span class="muted small">(opcional)</span></label>
          <textarea id="edInstructions" data-m="instructions" rows="2" placeholder="Ex.: Lê com atenção e responde ao teu ritmo.">${esc(ed.content.instructions || '')}</textarea></div>
        <details class="tool" data-ui="text" ${ed.ui.text ? 'open' : ''}>
          <summary>Texto de leitura <span class="muted small">(opcional — mostrado antes das perguntas)</span></summary>
          <textarea id="edText" data-m="text" rows="5" placeholder="Texto para a criança ler antes de responder.">${esc(ed.content.text || '')}</textarea>
        </details>
      </section>

      <section>
        <div class="row"><h2 style="margin:0">Perguntas</h2><span id="edQCount" class="badge grey"></span></div>
        <div id="qList"></div>
        <div class="add-q">
          <button class="secondary" data-act="add" data-type="multiple-choice">+ Escolha múltipla</button>
          <button class="secondary" data-act="add" data-type="true_false">+ Verdadeiro ou falso</button>
          <button class="secondary" data-act="add" data-type="written">+ Resposta aberta</button>
        </div>

        <details class="tool" data-ui="ai" ${ed.ui.ai ? 'open' : ''}>
          <summary>✨ Gerar perguntas com IA</summary>
          <p class="hint">Ajusta as quantidades, copia o pedido e cola-o na IA (ChatGPT, Claude, Gemini…). Depois cola aqui a resposta e escolhe substituir ou acrescentar às perguntas atuais.</p>
          <div class="grid">
            <div><label for="aiMc">Escolha múltipla</label><input id="aiMc" data-ai type="number" min="0" max="50" value="3"></div>
            <div><label for="aiTf">Verdadeiro ou falso</label><input id="aiTf" data-ai type="number" min="0" max="50" value="2"></div>
            <div><label for="aiWr">Resposta aberta</label><input id="aiWr" data-ai type="number" min="0" max="50" value="1"></div>
            <div><label for="aiExtra">Indicações extra</label><input id="aiExtra" data-ai placeholder="Ex.: contextos de compras no mercado"></div>
          </div>
          <label style="margin-top:12px" for="aiPrompt">Pedido para a IA</label>
          <textarea id="aiPrompt" class="ai-prompt" readonly></textarea>
          <div class="row mt"><button data-act="ai-copy">Copiar pedido</button><span id="aiInfo" class="hint" style="margin:0"></span></div>
          <label style="margin-top:14px" for="aiJson">Resposta da IA (JSON)</label>
          <textarea id="aiJson" class="code" style="min-height:160px" spellcheck="false" placeholder='{ "title": "…", "instructions": "…", "questions": [ … ] }'></textarea>
          <div class="row mt">
            <button data-act="ai-replace">Substituir perguntas</button>
            <button class="secondary" data-act="ai-append">Acrescentar às atuais</button>
          </div>
          <div id="aiMsg"></div>
          <details class="tool" style="background:#fff"><summary>Formato do JSON (referência)</summary><pre>${esc(A.schemaDoc)}</pre></details>
        </details>

        <details class="tool" data-ui="json" ${ed.ui.json ? 'open' : ''}>
          <summary>{ } Editar JSON do conteúdo</summary>
          <p class="hint">Para edições avançadas. Campos desconhecidos são preservados.</p>
          <textarea id="jsonEdit" class="code" spellcheck="false"></textarea>
          <div class="row mt"><button data-act="json-apply">Aplicar JSON</button><button class="secondary" data-act="json-refresh">Recarregar do editor</button></div>
          <div id="jsonMsg"></div>
        </details>

        <details class="tool" data-ui="preview" ${ed.ui.preview ? 'open' : ''}>
          <summary>👁 Pré-visualizar</summary>
          <div id="previewBox"></div>
        </details>
      </section>

      <div class="savebar"><div class="inner">
        <div class="status" id="edStatus"></div>
        <button class="secondary" data-act="back">Fechar</button>
        <button class="secondary" data-act="save-draft" id="edDraft">Guardar rascunho</button>
        <button class="success" data-act="save-publish" id="edPublish">Guardar e publicar</button>
      </div></div>`;
    renderTopics();
    renderQuestions();
    refreshAiPrompt();
    if (ed.ui.json) $('jsonEdit').value = JSON.stringify(ed.content, null, 2);
    if (ed.ui.preview) $('previewBox').innerHTML = A.renderPreview(ed.content);
    window.scrollTo({ top: 0 });
    if (ed.focusQuestionId) {
      const card = view.querySelector(`.q-card[data-qid="${CSS.escape(ed.focusQuestionId)}"]`);
      ed.focusQuestionId = null;
      if (card) { card.scrollIntoView({ block: 'center' }); card.classList.add('flash'); }
    }
  }

  function versionInfo(d, li) {
    if (!d) return 'Ficha nova: ao gravar é criada a versão 1. «Guardar rascunho» não a mostra aos pais; «Guardar e publicar» sim.';
    const l = d.latest, pub = d.versions.find((v) => v.publishedAt);
    const parts = [];
    if (!l) return 'Sem versões.';
    if (l.publishedAt) {
      parts.push(`<span class="badge ok">v${l.versionNumber} publicada</span> em ${A.fmtDate(l.publishedAt)}.`);
      parts.push(`Alterar perguntas, ano ou temas cria a <b>v${l.versionNumber + 1}</b> (quem já tem a ficha atribuída mantém a v${l.versionNumber}). O título é atualizado em todas as versões.`);
    } else if (pub) {
      parts.push(`<span class="badge warn">v${l.versionNumber} em rascunho</span> Os pais continuam a ver a v${pub.versionNumber}. Publica para a substituir.`);
    } else {
      parts.push(`<span class="badge warn">Rascunho</span> Nunca publicada: os pais ainda não a veem.`);
    }
    if (d.status === 'archived') parts.push('<span class="badge grey">Arquivada</span> «Guardar e publicar» volta a mostrá-la aos pais.');
    if (li && li.assignmentCount) parts.push(`${li.assignmentCount} atribuição(ões) a crianças.`);
    if (d.versions.length > 1) parts.push(`<span class="muted small">Histórico: ${d.versions.map((v) => `v${v.versionNumber}${v.publishedAt ? '' : ' (rascunho)'}`).join(', ')}</span>`);
    return parts.join(' ');
  }

  function renderTopics() {
    const topics = A.topicsFor(ed.subjectId, ed.year, ed.topicIds);
    $('edTopics').innerHTML = topics.map((t) => `
      <label class="${ed.topicIds.has(t.id) ? 'on' : ''}" ${t.archivedAt ? 'title="Tema arquivado: desmarca-o para gravar"' : ''}><input type="checkbox" data-topic="${t.id}" ${ed.topicIds.has(t.id) ? 'checked' : ''}> ${esc(t.name)}${t.archivedAt ? ' <span class="badge grey">arquivado</span>' : ''}</label>`).join('')
      + `<button class="sm secondary" data-act="new-topic">+ Novo tema</button>`
      + (topics.length ? '' : ' <span class="hint" style="margin:0">Ainda não há temas para esta disciplina e ano.</span>');
  }

  function renderQuestions() {
    const qs = ed.content.questions;
    $('qList').innerHTML = qs.length ? qs.map((q, i) => qCard(q, i, qs.length)).join('')
      : '<div class="empty">Sem perguntas. Adiciona abaixo ou gera-as com a IA.</div>';
    validate();
  }

  function qCard(q, i, total) {
    const typeOpts = Object.entries(A.typeLabel).map(([v, l]) => `<option value="${v}" ${q.type === v ? 'selected' : ''}>${l}</option>`).join('');
    let body = `<textarea data-f="prompt" rows="2" placeholder="${q.type === 'true_false' ? 'Afirmação (a criança decide se é verdadeira ou falsa)' : 'Enunciado da pergunta'}">${esc(q.prompt || '')}</textarea>`;
    if (q.type === 'multiple-choice') {
      const opts = Array.isArray(q.options) ? q.options : [];
      body += `<div class="opts">` + opts.map((o, j) => `
        <div class="opt ${o.id === q.correctAnswer ? 'correct' : ''}">
          <input type="radio" name="c-${i}" data-f="correct" value="${esc(o.id)}" ${o.id === q.correctAnswer ? 'checked' : ''} title="Marcar como resposta certa">
          <span class="letter">${letter(j)}</span>
          <input type="text" data-f="opt-text" data-o="${j}" value="${esc(o.text || '')}" placeholder="Opção ${letter(j)}">
          <button class="icon" data-act="opt-del" data-o="${j}" ${opts.length <= 2 ? 'disabled' : ''} title="Remover opção">✕</button>
        </div>`).join('') + `</div>
        <div class="row"><button class="sm secondary" data-act="opt-add" ${opts.length >= 8 ? 'disabled' : ''}>+ Opção</button>
        <span class="hint" style="margin:0">Marca o círculo da opção certa.</span></div>`;
    } else if (q.type === 'true_false') {
      body += `<div class="tf">
        <label class="${q.correctAnswer === true ? 'on' : ''}"><input type="radio" name="tf-${i}" data-f="tf" value="true" ${q.correctAnswer === true ? 'checked' : ''}> Verdadeiro</label>
        <label class="${q.correctAnswer === false ? 'on' : ''}"><input type="radio" name="tf-${i}" data-f="tf" value="false" ${q.correctAnswer === false ? 'checked' : ''}> Falso</label>
      </div>`;
    } else {
      body += `<p class="hint" style="margin:8px 0">A criança responde por escrito ou no caderno; é corrigida pelos pais.</p>`;
    }
    const expLabel = q.type === 'written' ? 'Resposta esperada e critérios para os pais (não é mostrada à criança)' : 'Explicação mostrada à criança na correção';
    body += `<label class="small" style="margin-top:10px">${expLabel}</label>
      <textarea data-f="explanation" rows="2">${esc(q.explanation || '')}</textarea><div class="q-err"></div>`;
    return `<div class="q-card" data-q="${i}" data-qid="${esc(q.id)}">
      <div class="q-head"><span class="num">${i + 1}</span><select data-f="type">${typeOpts}</select>
        <code title="Identificador interno da pergunta">${esc(q.id)}</code><span class="spacer"></span>
        <button class="icon" data-act="q-up" ${i === 0 ? 'disabled' : ''} title="Subir">↑</button>
        <button class="icon" data-act="q-down" ${i === total - 1 ? 'disabled' : ''} title="Descer">↓</button>
        <button class="icon" data-act="q-dup" title="Duplicar">⧉</button>
        <button class="icon" data-act="q-del" title="Apagar pergunta">🗑</button>
      </div>${body}</div>`;
  }

  // ---------- Validação ----------
  function metaErrors() {
    const e = [];
    if (!ed.title.trim()) e.push('Indica o título.');
    if (ed.title.trim().length > 160) e.push('O título tem mais de 160 caracteres.');
    if (!ed.subjectId) e.push('Escolhe a disciplina.');
    if (!ed.topicIds.size) e.push('Escolhe pelo menos um tema.');
    return e;
  }

  function validate() {
    const { errors } = A.checkContent(ed.content);
    const byQ = new Map();
    errors.filter((e) => e.q != null).forEach((e) => byQ.set(e.q, [...(byQ.get(e.q) || []), e.text]));
    document.querySelectorAll('#qList .q-card').forEach((card) => {
      const list = byQ.get(Number(card.dataset.q)) || [];
      card.classList.toggle('has-err', list.length > 0);
      card.querySelector('.q-err').textContent = list.join(' ');
    });
    const general = [...metaErrors(), ...errors.filter((e) => e.q == null).map((e) => e.text)];
    const qErrCount = byQ.size;
    const counts = A.countByType(ed.content.questions);
    $('edQCount').textContent = `${ed.content.questions.length} • ` +
      (Object.entries(counts).map(([t, c]) => `${c} ${A.typeShort[t] || t}`).join(' • ') || 'nenhuma');
    const ok = general.length === 0 && qErrCount === 0;
    let status = ok ? '<span class="badge ok">Pronta a gravar</span>'
      : `<span class="badge err">${general.length + qErrCount} problema(s)</span> <span class="small">${esc(general.concat(qErrCount ? [`${qErrCount} pergunta(s) por completar.`] : []).join(' '))}</span>`;
    if (ed.dirty) status += ' <span class="badge warn">Alterações por gravar</span>';
    if (ed.data && latestPublished() && contentChanged()) status += ` <span class="badge">Vai criar a v${ed.data.latest.versionNumber + 1}</span>`;
    $('edStatus').innerHTML = status;
    $('edDraft').disabled = !ok;
    $('edPublish').disabled = !ok;
    $('edDraft').title = latestPublished() ? 'Grava sem mudar o que os pais veem (uma nova versão fica em rascunho)' : 'Grava sem mostrar aos pais';
    return ok;
  }

  function changed({ questions = false, preview = true } = {}) {
    ed.dirty = true;
    if (questions) renderQuestions(); else validate();
    if (preview && ed.ui.preview) $('previewBox').innerHTML = A.renderPreview(ed.content);
  }

  // ---------- Perguntas ----------
  function newQuestionId(taken = new Set(ed.content.questions.map((q) => q.id))) {
    let n = ed.content.questions.length + 1;
    while (taken.has('q' + n)) n++;
    return 'q' + n;
  }
  function newOptionId(q) {
    const used = new Set(q.options.map((o) => o.id));
    for (let c = 97; c < 123; c++) if (!used.has(String.fromCharCode(c))) return String.fromCharCode(c);
    return 'o' + Date.now();
  }
  function blankQuestion(type) {
    const q = { id: newQuestionId(), type, prompt: '' };
    if (type === 'multiple-choice') { q.options = [{ id: 'a', text: '' }, { id: 'b', text: '' }, { id: 'c', text: '' }]; q.correctAnswer = null; }
    if (type === 'true_false') q.correctAnswer = null;
    return q;
  }
  function changeType(q, type) {
    if (q.type === type) return;
    q.type = type;
    delete q.options; delete q.correctAnswer;
    if (type === 'multiple-choice') { q.options = [{ id: 'a', text: '' }, { id: 'b', text: '' }, { id: 'c', text: '' }]; q.correctAnswer = null; }
    if (type === 'true_false') q.correctAnswer = null;
  }

  // ---------- IA ----------
  const int = (v) => Math.max(0, Math.min(50, parseInt(v, 10) || 0));
  function refreshAiPrompt() {
    if (!$('aiPrompt')) return;
    const counts = { mc: int($('aiMc').value), tf: int($('aiTf').value), wr: int($('aiWr').value) };
    const total = counts.mc + counts.tf + counts.wr;
    $('aiInfo').textContent = total < 1 || total > 50 ? 'O total de perguntas tem de estar entre 1 e 50.' : `${total} perguntas no total.`;
    $('aiPrompt').value = A.buildAiPrompt({
      year: ed.year, subject: A.subject(ed.subjectId)?.name || '', counts, extra: $('aiExtra').value.trim(), title: ed.title.trim(),
      topics: [...ed.topicIds].map((id) => A.topic(id)?.name).filter(Boolean),
    });
  }

  function applyAi(mode) {
    const r = A.normalizeImport($('aiJson').value);
    if (r.errors.length) {
      $('aiMsg').innerHTML = A.msg('err', `<b>${r.errors.length} erro(s) no JSON:</b><ul>${r.errors.map((e) => `<li>${esc(e)}</li>`).join('')}</ul>`);
      return;
    }
    const current = ed.content.questions;
    if (mode === 'replace') {
      if (current.length && !confirm(`Substituir as ${current.length} perguntas atuais pelas ${r.content.questions.length} da IA?`)) return;
      ed.content.questions = r.content.questions;
    } else {
      const taken = new Set(current.map((q) => q.id));
      const added = r.content.questions.map((q) => {
        const copy = { ...q };
        if (taken.has(copy.id)) copy.id = newQuestionId(taken);
        taken.add(copy.id);
        return copy;
      });
      ed.content.questions = current.concat(added);
    }
    for (const key of ['instructions', 'text']) {
      if (r.content[key] && (mode === 'replace' || !ed.content[key])) ed.content[key] = r.content[key];
    }
    if (r.title && !ed.title.trim()) ed.title = r.title;
    if (ed.content.text) ed.ui.text = true;
    ed.dirty = true;
    render();
    $('aiMsg').innerHTML = A.msg('ok', `${r.content.questions.length} pergunta(s) ${mode === 'replace' ? 'carregadas' : 'acrescentadas'}. Revê-as acima antes de gravar.`)
      + (r.warnings.length ? A.msg('warn', `<b>Avisos:</b><ul>${r.warnings.map((e) => `<li>${esc(e)}</li>`).join('')}</ul>`) : '');
  }

  function applyJson() {
    let data;
    try { data = JSON.parse($('jsonEdit').value); }
    catch (e) { $('jsonMsg').innerHTML = A.msg('err', 'JSON inválido: ' + esc(e.message)); return; }
    if (Array.isArray(data)) data = { ...ed.content, questions: data };
    if (!data || typeof data !== 'object' || !Array.isArray(data.questions)) {
      $('jsonMsg').innerHTML = A.msg('err', 'O conteúdo tem de ser um objeto com a lista "questions".');
      return;
    }
    ed.content = data;
    ed.dirty = true;
    render();
    $('jsonMsg').innerHTML = A.msg('ok', 'JSON aplicado. Os problemas aparecem em cada pergunta.');
  }

  // ---------- Gravar ----------
  async function save(publish) {
    if (!validate()) return;
    const content = A.cleanContent(ed.content);
    const d = ed.data;
    const newVersion = d && latestPublished() && contentChanged();
    if (publish && newVersion && ed.listItem && ed.listItem.assignmentCount) {
      if (!confirm(`Publicar a v${d.latest.versionNumber + 1}?\n\nAs ${ed.listItem.assignmentCount} atribuição(ões) existentes continuam com a versão que já tinham; as novas atribuições usam a nova versão.`)) return;
    }
    $('edDraft').disabled = $('edPublish').disabled = true;
    try {
      const r = await A.rpc('admin_save_worksheet', {
        p_worksheet_id: ed.id || null, p_subject_id: ed.subjectId, p_school_year: Number(ed.year),
        p_topic_ids: [...ed.topicIds], p_title: ed.title.trim(), p_content: content, p_publish: !!publish,
      });
      const text = r.newVersion && r.published ? `Versão ${r.versionNumber} criada e publicada ✓`
        : r.newVersion ? `Versão ${r.versionNumber} gravada como rascunho (os pais não a veem ainda).`
        : r.publishedNow ? `Versão ${r.versionNumber} publicada ✓`
        : r.published ? 'Alterações gravadas ✓' : 'Rascunho gravado ✓';
      ed.dirty = false;
      await A.app.reload();
      await E.open(r.worksheetId);
      A.toast('ok', text);
    } catch (e) {
      A.fail(e);
      validate();
    }
  }

  // ---------- Eventos ----------
  E.init = () => {
    const view = $('wsEditorView');

    view.addEventListener('input', (ev) => {
      const el = ev.target;
      if (!ed) return;
      if (el.dataset.ai !== undefined) { refreshAiPrompt(); return; }
      const m = el.dataset.m;
      if (m === 'title') { ed.title = el.value; changed({ preview: false }); return; }
      if (m === 'instructions' || m === 'text') { ed.content[m] = el.value; changed(); return; }
      const card = el.closest('.q-card');
      if (!card) return;
      const q = ed.content.questions[Number(card.dataset.q)];
      const f = el.dataset.f;
      if (f === 'prompt' || f === 'explanation') { q[f] = el.value; changed(); }
      else if (f === 'opt-text') { q.options[Number(el.dataset.o)].text = el.value; changed(); }
    });

    view.addEventListener('change', (ev) => {
      const el = ev.target;
      if (!ed) return;
      const m = el.dataset.m;
      if (m === 'subject' || m === 'year') {
        if (m === 'subject') ed.subjectId = el.value; else ed.year = Number(el.value);
        const valid = new Set(A.topicsFor(ed.subjectId, ed.year).map((t) => t.id));
        const removed = [...ed.topicIds].filter((id) => !valid.has(id));
        removed.forEach((id) => ed.topicIds.delete(id));
        if (removed.length) A.toast('warn', `${removed.length} tema(s) desmarcado(s): não pertencem à disciplina/ano escolhidos.`);
        renderTopics(); refreshAiPrompt(); changed({ preview: false });
        return;
      }
      if (el.dataset.topic) {
        if (el.checked) ed.topicIds.add(el.dataset.topic); else ed.topicIds.delete(el.dataset.topic);
        el.closest('label').classList.toggle('on', el.checked);
        refreshAiPrompt(); changed({ preview: false });
        return;
      }
      const card = el.closest('.q-card');
      if (!card) return;
      const q = ed.content.questions[Number(card.dataset.q)];
      const f = el.dataset.f;
      if (f === 'type') { changeType(q, el.value); changed({ questions: true }); }
      else if (f === 'correct') {
        q.correctAnswer = el.value;
        card.querySelectorAll('.opt').forEach((row) => row.classList.toggle('correct', row.querySelector('[data-f=correct]').checked));
        changed();
      } else if (f === 'tf') {
        q.correctAnswer = el.value === 'true';
        card.querySelectorAll('.tf label').forEach((l) => l.classList.toggle('on', l.querySelector('input').checked));
        changed();
      }
    });

    // Guarda o estado aberto/fechado dos painéis entre renders.
    view.addEventListener('toggle', (ev) => {
      const key = ev.target.dataset && ev.target.dataset.ui;
      if (!ed || !key) return;
      ed.ui[key] = ev.target.open;
      if (key === 'json' && ev.target.open) $('jsonEdit').value = JSON.stringify(ed.content, null, 2);
      if (key === 'preview' && ev.target.open) $('previewBox').innerHTML = A.renderPreview(ed.content);
      if (key === 'ai' && ev.target.open) refreshAiPrompt();
    }, true);

    view.addEventListener('click', async (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn || !ed) return;
      ev.preventDefault();
      const act = btn.dataset.act;
      const card = btn.closest('.q-card');
      const i = card ? Number(card.dataset.q) : -1;
      const qs = ed.content.questions;
      switch (act) {
        case 'back': close(); return;
        case 'save-draft': save(false); return;
        case 'save-publish': save(true); return;
        case 'add': {
          qs.push(blankQuestion(btn.dataset.type));
          changed({ questions: true });
          const cards = document.querySelectorAll('#qList .q-card');
          const last = cards[cards.length - 1];
          last.scrollIntoView({ block: 'center', behavior: 'smooth' });
          last.querySelector('[data-f=prompt]').focus({ preventScroll: true });
          return;
        }
        case 'q-up': [qs[i - 1], qs[i]] = [qs[i], qs[i - 1]]; changed({ questions: true }); return;
        case 'q-down': [qs[i + 1], qs[i]] = [qs[i], qs[i + 1]]; changed({ questions: true }); return;
        case 'q-dup': { const copy = clone(qs[i]); copy.id = newQuestionId(); qs.splice(i + 1, 0, copy); changed({ questions: true }); return; }
        case 'q-del':
          if ((qs[i].prompt || '').trim() && !confirm(`Apagar a pergunta ${i + 1}?`)) return;
          qs.splice(i, 1); changed({ questions: true }); return;
        case 'opt-add': { const q = qs[i]; q.options.push({ id: newOptionId(q), text: '' }); changed({ questions: true });
          const inputs = document.querySelectorAll(`.q-card[data-q="${i}"] [data-f=opt-text]`); inputs[inputs.length - 1].focus(); return; }
        case 'opt-del': { const q = qs[i]; const [removed] = q.options.splice(Number(btn.dataset.o), 1);
          if (removed && removed.id === q.correctAnswer) q.correctAnswer = null; changed({ questions: true }); return; }
        case 'new-topic': {
          if (!ed.subjectId) { A.toast('warn', 'Escolhe primeiro a disciplina.'); return; }
          const t = await A.topics.editTopic(null, { subjectId: ed.subjectId, year: ed.year, fixed: true });
          if (t) { ed.topicIds.add(t.id); renderTopics(); refreshAiPrompt(); changed({ preview: false }); }
          return;
        }
        case 'ai-copy': A.copy($('aiPrompt').value, btn); return;
        case 'ai-replace': applyAi('replace'); return;
        case 'ai-append': applyAi('append'); return;
        case 'json-apply': applyJson(); return;
        case 'json-refresh': $('jsonEdit').value = JSON.stringify(ed.content, null, 2); $('jsonMsg').innerHTML = ''; return;
      }
    });
  };
})();
