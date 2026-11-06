// Lista de fichas: filtros, publicar/arquivar e apagar.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const W = A.worksheets = {};

  const statusBadge = (w) => ({
    published: '<span class="badge ok">Publicada</span>',
    draft: '<span class="badge warn">Rascunho</span>',
    archived: '<span class="badge grey">Arquivada</span>',
  })[w.status] || `<span class="badge">${esc(w.status)}</span>`;
  const hasPendingDraft = (w) => w.latest && !w.latest.publishedAt && w.publishedVersionCount > 0;

  W.render = () => {
    const fs = $('fSubject'), ft = $('fTopic');
    const subject = fs.value, topic = ft.value;
    fs.innerHTML = A.subjectOptions(subject, 'Todas as disciplinas');
    const topics = A.state.topics
      .filter((t) => !t.archivedAt && (!fs.value || t.subjectId === fs.value) && (!$('fYear').value || t.schoolYear === Number($('fYear').value)))
      .sort((a, b) => a.schoolYear - b.schoolYear || a.name.localeCompare(b.name, 'pt'));
    ft.innerHTML = '<option value="">Todos os temas</option>' + topics.map((t) =>
      `<option value="${t.id}" ${t.id === topic ? 'selected' : ''}>${t.schoolYear}.º • ${esc(t.name)}${fs.value ? '' : ' (' + esc(A.subject(t.subjectId)?.name || '') + ')'}</option>`).join('');
    renderList();
  };

  function filtered() {
    const q = A.norm($('fSearch').value), subject = $('fSubject').value, year = Number($('fYear').value) || null;
    const topic = $('fTopic').value, status = $('fStatus').value;
    return A.state.worksheets.filter((w) => {
      const l = w.latest || {};
      if (subject && w.subjectId !== subject) return false;
      if (year && l.schoolYear !== year) return false;
      if (topic && !(l.topicIds || []).includes(topic)) return false;
      if (status === 'pending' && !hasPendingDraft(w)) return false;
      if (status === 'reports' && !w.openReportCount) return false;
      if (['published', 'draft', 'archived'].includes(status) && w.status !== status) return false;
      if (q) {
        const hay = A.norm([w.title, w.subjectName, ...(l.topicIds || []).map((id) => A.topic(id)?.name || '')].join(' '));
        if (!q.split(/\s+/).every((part) => hay.includes(part))) return false;
      }
      return true;
    });
  }

  function renderList() {
    const items = filtered();
    $('wsCount').textContent = items.length === A.state.worksheets.length ? `${items.length}` : `${items.length} de ${A.state.worksheets.length}`;
    if (!items.length) {
      $('wsList').innerHTML = `<div class="empty">${A.state.worksheets.length ? 'Nenhuma ficha corresponde aos filtros.' : 'Ainda não há fichas. Cria a primeira com «+ Nova ficha».'}</div>`;
      return;
    }
    $('wsList').innerHTML = items.map((w) => {
      const l = w.latest || {};
      const topics = (l.topicIds || []).map((id) => A.topic(id)?.name).filter(Boolean);
      const counts = [l.choiceCount && `${l.choiceCount} EM`, l.trueFalseCount && `${l.trueFalseCount} V/F`, l.writtenCount && `${l.writtenCount} abertas`].filter(Boolean).join(' • ');
      const canDelete = w.publishedVersionCount === 0;
      return `<div class="ws ${w.status === 'archived' ? 'archived' : ''}">
        <div>
          <div class="title" data-act="edit" data-id="${w.id}">${esc(w.title)}</div>
          <div class="meta">${esc(w.subjectName)} • ${l.schoolYear || '?'}.º Ano • ${topics.length ? topics.map(esc).join(', ') : '<i>sem tema</i>'}</div>
          <div class="badges">
            ${statusBadge(w)}
            ${hasPendingDraft(w) ? '<span class="badge warn" title="Há alterações gravadas que os responsáveis ainda não veem">Rascunho por publicar</span>' : ''}
            <span class="badge grey" title="Versão mais recente">v${l.versionNumber || 1}</span>
            <span class="badge grey">${l.questionCount || 0} perguntas${counts ? ' • ' + counts : ''}</span>
            ${w.assignmentCount ? `<span class="badge grey" title="Atribuições a crianças (todas as versões)">${w.assignmentCount} atribuiç${w.assignmentCount === 1 ? 'ão' : 'ões'}</span>` : ''}
            ${w.openReportCount ? `<button class="badge err" data-act="reports" data-id="${w.id}" title="Ver relatos">⚠ ${w.openReportCount} relato${w.openReportCount === 1 ? '' : 's'}</button>` : ''}
            ${w.isSample ? '<span class="badge grey">Exemplo</span>' : ''}
          </div>
        </div>
        <div class="actions">
          <button class="sm" data-act="edit" data-id="${w.id}">Editar</button>
          ${w.status === 'archived'
            ? `<button class="sm secondary" data-act="publish" data-id="${w.id}" ${w.publishedVersionCount ? '' : 'disabled'}>Reativar</button>`
            : w.publishedVersionCount ? `<button class="sm secondary" data-act="archive" data-id="${w.id}">Arquivar</button>` : ''}
          <button class="sm danger" data-act="delete" data-id="${w.id}" ${canDelete ? '' : 'disabled title="Fichas publicadas não se apagam: arquiva-as"'}>Apagar</button>
        </div>
      </div>`;
    }).join('');
  }

  async function setStatus(id, status) {
    const w = A.state.worksheets.find((x) => x.id === id);
    if (status === 'archived' && !confirm(`Arquivar «${w.title}»?\n\nDeixa de aparecer aos responsáveis para novas atribuições. As fichas já atribuídas continuam disponíveis para as crianças.`)) return;
    try {
      await A.rpc('admin_set_worksheet_status', { p_id: id, p_status: status });
      await A.app.reload({ catalogue: false });
      A.toast('ok', status === 'archived' ? 'Ficha arquivada.' : 'Ficha reativada: volta a aparecer aos responsáveis.');
    } catch (e) { A.fail(e); }
  }

  async function remove(id) {
    const w = A.state.worksheets.find((x) => x.id === id);
    if (!w || !confirm(`Apagar definitivamente o rascunho «${w.title}»?`)) return;
    try { await A.rpc('admin_delete_worksheet', { p_id: id }); await A.app.reload(); A.toast('ok', 'Ficha apagada.'); }
    catch (e) { A.fail(e); }
  }

  W.showForTopic = (topicId) => {
    const t = A.topic(topicId);
    A.app.showTab('worksheets');
    W.closeEditor();
    $('fSearch').value = ''; $('fStatus').value = '';
    $('fSubject').value = t ? t.subjectId : '';
    $('fYear').value = t ? String(t.schoolYear) : '';
    W.render();
    $('fTopic').value = topicId;
    renderList();
  };

  W.closeEditor = () => { $('wsEditorView').hidden = true; $('wsEditorView').innerHTML = ''; $('wsListView').hidden = false; };

  W.init = () => {
    ['fSearch', 'fTopic', 'fStatus'].forEach((id) => $(id).addEventListener('input', renderList));
    ['fSubject', 'fYear'].forEach((id) => $(id).addEventListener('input', W.render));
    $('newWorksheet').addEventListener('click', () => A.editor.open(null));
    $('wsList').addEventListener('click', (ev) => {
      const el = ev.target.closest('[data-act]');
      if (!el) return;
      const id = el.dataset.id;
      ({
        edit: () => A.editor.open(id),
        archive: () => setStatus(id, 'archived'),
        publish: () => setStatus(id, 'published'),
        delete: () => remove(id),
        reports: () => A.reports.showForWorksheet(id),
      })[el.dataset.act]?.();
    });
  };
})();
