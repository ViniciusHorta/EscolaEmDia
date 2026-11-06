// Disciplinas e temas (CRUD).
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const T = A.topics = {};

  T.render = () => {
    renderSubjects();
    const subjectSel = $('tSubject'), current = subjectSel.value;
    subjectSel.innerHTML = A.subjectOptions(current, 'Todas as disciplinas');
    renderRows();
  };

  function renderSubjects() {
    const list = $('subjectList');
    if (!A.state.subjects.length) { list.innerHTML = '<span class="muted">Ainda não há disciplinas.</span>'; return; }
    list.innerHTML = A.state.subjects.map((s) => `
      <span class="chip">${esc(s.name)} <span class="n">${s.topicCount} temas • ${s.worksheetCount} fichas</span>
        <button class="icon" data-act="edit-subject" data-id="${s.id}" title="Renomear">✎</button>
        <button class="icon" data-act="del-subject" data-id="${s.id}" title="${s.topicCount || s.worksheetCount ? 'Tem temas ou fichas' : 'Apagar'}" ${s.topicCount || s.worksheetCount ? 'disabled' : ''}>🗑</button>
      </span>`).join('');
  }

  function renderRows() {
    const rows = filteredTopics()
      .sort((a, b) => (A.subject(a.subjectId)?.name || '').localeCompare(A.subject(b.subjectId)?.name || '', 'pt')
        || a.schoolYear - b.schoolYear || a.name.localeCompare(b.name, 'pt'));
    const empty = rows.filter((t) => !t.inUse);
    $('tBulk').hidden = empty.length === 0;
    $('tBulkInfo').textContent = `${empty.length} tema(s) sem fichas neste filtro.`;
    $('tBulkDelete').textContent = `Apagar ${empty.length === 1 ? 'o tema' : `os ${empty.length} temas`} sem fichas`;
    if (!rows.length) { $('topicRows').innerHTML = `<tr><td colspan="5" class="empty">Nenhum tema encontrado.</td></tr>`; return; }
    let lastGroup = '';
    $('topicRows').innerHTML = rows.map((t) => {
      const subject = A.subject(t.subjectId)?.name || '?';
      const group = `${subject} • ${t.schoolYear}.º Ano`;
      const head = group !== lastGroup ? `<tr class="group"><td colspan="5">${esc(group)}</td></tr>` : '';
      lastGroup = group;
      const history = t.historyWorksheets || [];
      const usageCell = [
        t.worksheetCount ? `<button class="badge" data-act="show-ws" data-id="${t.id}" title="Ver fichas cuja versão atual usa este tema">${t.worksheetCount} ficha${t.worksheetCount === 1 ? '' : 's'}</button>` : '',
        history.length ? `<button class="badge ${history.some((h) => h.live) ? 'warn' : 'grey'}" data-act="show-history" data-id="${t.id}" title="Fichas que já não usam o tema na versão atual, mas ainda o usam em versões anteriores">${history.length} em versões antigas</button>` : '',
      ].filter(Boolean).join(' ') || '<span class="muted small">—</span>';
      const deleteTitle = t.worksheetCount ? 'Usado por fichas' : history.length ? 'Ainda usado em versões antigas de fichas (histórico imutável). Podes arquivá-lo.' : '';
      const block = archiveBlock(t);
      const archiveBtn = t.archivedAt
        ? `<button class="sm secondary" data-act="unarchive-topic" data-id="${t.id}" title="Volta a aparecer no editor e aos responsáveis">Reativar</button>`
        : `<button class="sm secondary" data-act="archive-topic" data-id="${t.id}" ${block ? `disabled title="${esc(block)}"` : 'title="Esconde o tema do editor e da área do responsável, sem mexer no histórico"'}>Arquivar</button>`;
      return head + `<tr ${t.archivedAt ? 'style="opacity:.65"' : ''}>
        <td><b>${esc(t.name)}</b>${t.archivedAt ? ` <span class="badge grey" title="Arquivado em ${A.fmtDate(t.archivedAt)}">Arquivado</span>` : ''}</td><td>${esc(subject)}</td><td>${t.schoolYear}.º</td>
        <td>${usageCell}</td>
        <td class="actions">
          <button class="sm secondary" data-act="edit-topic" data-id="${t.id}">Editar</button>
          ${archiveBtn}
          <button class="sm danger" data-act="del-topic" data-id="${t.id}" ${t.inUse ? `disabled title="${deleteTitle}"` : ''}>Apagar</button>
        </td></tr>`;
    }).join('');
  }

  function filteredTopics() {
    const q = A.norm($('tSearch').value), subjectId = $('tSubject').value, year = $('tYear').value, usage = $('tUsage').value;
    return A.state.topics.filter((t) => (!subjectId || t.subjectId === subjectId) && (!year || t.schoolYear === Number(year))
      && (!q || A.norm(t.name).includes(q))
      && (usage === 'archived' ? !!t.archivedAt : !t.archivedAt && (!usage
        || (usage === 'empty' ? !t.inUse : usage === 'history' ? t.inUse && !t.worksheetCount : t.worksheetCount > 0))));
  }

  // Motivo pelo qual o tema não pode ser arquivado (espelha a regra de admin_set_topic_archived), ou null.
  function archiveBlock(t) {
    if (t.worksheetCount) return `Usado na versão atual de ${t.worksheetCount} ficha(s): retira-o dessas fichas primeiro.`;
    if ((t.historyWorksheets || []).some((h) => h.live)) return 'Ainda visível aos responsáveis numa versão publicada: publica primeiro as fichas onde o retiraste.';
    return null;
  }

  async function setArchived(id, archived) {
    const t = A.topic(id);
    if (!t) return;
    if (archived && !confirm(`Arquivar o tema «${t.name}»?\n\nDeixa de aparecer no editor de fichas e na área do responsável. As versões antigas das fichas não são alteradas e podes reativá-lo a qualquer momento.`)) return;
    try {
      await A.rpc('admin_set_topic_archived', { p_id: id, p_archived: archived });
      await A.app.reload({ worksheets: false });
      A.toast('ok', archived ? `Tema «${esc(t.name)}» arquivado.` : `Tema «${esc(t.name)}» reativado.`);
    } catch (e) { A.fail(e); }
  }

  // Apaga todos os temas sem fichas do filtro atual (a base volta a confirmar que cada um não está em uso).
  async function deleteEmptyTopics() {
    const empty = filteredTopics().filter((t) => !t.inUse);
    if (!empty.length) return;
    const names = empty.slice(0, 15).map((t) => `• ${t.name} (${A.subject(t.subjectId)?.name || '?'}, ${t.schoolYear}.º)`).join('\n');
    if (!confirm(`Apagar ${empty.length} tema(s) sem fichas?\n\n${names}${empty.length > 15 ? `\n… e mais ${empty.length - 15}` : ''}`)) return;
    $('tBulkDelete').disabled = true;
    let ok = 0;
    const failed = [];
    for (const t of empty) {
      try { await A.rpc('admin_delete_topic', { p_id: t.id }); ok++; }
      catch (e) { failed.push(`${t.name}: ${e.message}`); }
    }
    $('tBulkDelete').disabled = false;
    await A.app.reload({ worksheets: false });
    if (ok) A.toast('ok', `${ok} tema(s) apagado(s).`);
    if (failed.length) A.toast('err', `Não foi possível apagar ${failed.length}: ${esc(failed.join(' • '))}`, 8000);
  }

  // ---------- Disciplinas ----------
  async function editSubject(id) {
    const s = id ? A.subject(id) : null;
    const saved = await A.dialog({
      title: s ? 'Renomear disciplina' : 'Nova disciplina',
      body: `<div class="field"><label for="dSubjectName">Nome</label><input id="dSubjectName" maxlength="80" required value="${esc(s?.name || '')}"></div>`,
      onSubmit: async () => A.rpc('admin_save_subject', { p_id: id || null, p_name: $('dSubjectName').value }),
    });
    if (!saved) return;
    A.toast('ok', s ? 'Disciplina renomeada.' : `Disciplina «${esc(saved.name)}» criada.`);
    await A.app.reload({ worksheets: !!s });
  }

  async function deleteSubject(id) {
    const s = A.subject(id);
    if (!s || !confirm(`Apagar a disciplina «${s.name}»?`)) return;
    try { await A.rpc('admin_delete_subject', { p_id: id }); A.toast('ok', 'Disciplina apagada.'); await A.app.reload({ worksheets: false }); }
    catch (e) { A.fail(e); }
  }

  // ---------- Temas ----------
  // Também usado pelo editor de fichas (com disciplina e ano fixos). Devolve o tema gravado ou null.
  T.editTopic = async (id, defaults = {}) => {
    const t = id ? A.topic(id) : null;
    const locked = !!(t && t.inUse);
    const fixed = !!defaults.fixed;
    const subjectId = t?.subjectId || defaults.subjectId || $('tSubject').value || A.state.subjects[0]?.id;
    const year = t?.schoolYear || defaults.year || Number($('tYear').value) || 1;
    if (!A.state.subjects.length) { A.toast('warn', 'Cria primeiro uma disciplina.'); return null; }
    const saved = await A.dialog({
      title: t ? 'Editar tema' : 'Novo tema',
      body: `
        <div class="field"><label for="dTopicName">Nome do tema</label><input id="dTopicName" maxlength="120" required value="${esc(t?.name || '')}"></div>
        <div class="grid">
          <div class="field"><label for="dTopicSubject">Disciplina</label><select id="dTopicSubject" ${locked || fixed ? 'disabled' : ''}>${A.subjectOptions(subjectId)}</select></div>
          <div class="field"><label for="dTopicYear">Ano</label><select id="dTopicYear" ${locked || fixed ? 'disabled' : ''}>${A.yearOptions(year)}</select></div>
        </div>
        ${locked ? `<p class="hint">${t.worksheetCount ? `Usado por ${t.worksheetCount} ficha(s)` : 'Usado em versões antigas de fichas'}: só o nome pode ser alterado.</p>` : ''}`,
      onSubmit: async () => A.rpc('admin_save_topic', {
        p_id: id || null, p_subject_id: $('dTopicSubject').value, p_school_year: Number($('dTopicYear').value), p_name: $('dTopicName').value,
      }),
    });
    if (!saved) return null;
    A.toast('ok', t ? 'Tema atualizado.' : `Tema «${esc(saved.name)}» criado.`);
    await A.app.reload({ worksheets: false });
    return saved;
  };

  // Fichas que já não usam o tema na versão atual, mas o mantêm em versões anteriores (imutáveis).
  function showHistory(id) {
    const t = A.topic(id);
    const history = (t && t.historyWorksheets) || [];
    const items = history.map((h) => {
      const w = A.state.worksheets.find((x) => x.id === h.worksheetId);
      const versions = h.versionNumbers.map((n) => 'v' + n).join(', ');
      return `<li style="margin-bottom:10px"><b>${esc(w ? w.title : h.worksheetId)}</b>
        <div class="small muted">Tema presente em ${versions}${w && w.latest ? ` • versão atual: v${w.latest.versionNumber}${w.latest.publishedAt ? '' : ' (rascunho)'}` : ''}</div>
        <div class="row" style="margin-top:4px">
          ${h.live ? '<span class="badge warn" title="A versão atual é um rascunho: os responsáveis ainda veem a versão publicada com este tema">Ainda visível aos responsáveis</span>' : ''}
          ${h.assigned ? '<span class="badge grey">Atribuída a crianças</span>' : ''}
          <button type="button" class="sm secondary" data-open-ws="${h.worksheetId}">Abrir ficha</button>
        </div></li>`;
    }).join('');
    const live = history.some((h) => h.live);
    A.dialog({
      title: `«${t.name}» em versões antigas`,
      ok: 'Fechar',
      info: true,
      body: `<p class="hint">Estas fichas já não usam o tema na versão atual, mas versões anteriores continuam ligadas a ele.
        As versões publicadas não podem ser alteradas (podem estar atribuídas a crianças), por isso o tema não pode ser apagado — pode ser renomeado ou <b>arquivado</b>.</p>
        ${live ? '<p class="msg warn" style="margin-top:0">Há fichas com a remoção do tema ainda em rascunho: publica-as para que os responsáveis deixem de ver o tema.</p>' : ''}
        <ul style="padding-left:18px; margin:0">${items}</ul>`,
    });
    $('dlgBody').onclick = (ev) => {
      const btn = ev.target.closest('[data-open-ws]');
      if (!btn) return;
      $('dlgBody').onclick = null;
      $('dlg').close();
      A.editor.open(btn.dataset.openWs);
    };
  }

  async function deleteTopic(id) {
    const t = A.topic(id);
    if (!t || !confirm(`Apagar o tema «${t.name}»?`)) return;
    try { await A.rpc('admin_delete_topic', { p_id: id }); A.toast('ok', 'Tema apagado.'); await A.app.reload({ worksheets: false }); }
    catch (e) { A.fail(e); }
  }

  // ---------- Eventos ----------
  T.init = () => {
    $('newSubject').addEventListener('click', () => editSubject(null));
    $('newTopic').addEventListener('click', () => T.editTopic(null));
    ['tSearch', 'tSubject', 'tYear', 'tUsage'].forEach((id) => $(id).addEventListener('input', renderRows));
    $('tBulkDelete').addEventListener('click', deleteEmptyTopics);
    $('tab-topics').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      const id = btn.dataset.id;
      ({
        'edit-subject': () => editSubject(id),
        'del-subject': () => deleteSubject(id),
        'edit-topic': () => T.editTopic(id),
        'del-topic': () => deleteTopic(id),
        'show-ws': () => A.worksheets.showForTopic(id),
        'show-history': () => showHistory(id),
        'archive-topic': () => setArchived(id, true),
        'unarchive-topic': () => setArchived(id, false),
      })[btn.dataset.act]?.();
    });
  };
})();
