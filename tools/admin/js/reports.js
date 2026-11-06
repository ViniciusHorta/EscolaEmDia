// Relatos de problemas em perguntas, feitos pelos pais na revisão.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const R = A.reports = {};
  let worksheetFilter = null;

  const reasonLabel = { wrong_answer: 'Resposta errada', unclear: 'Pouco clara', typo: 'Erro ortográfico', inappropriate: 'Inapropriada', other: 'Outro' };
  const statusLabel = { open: ['Aberto', 'err'], in_review: ['Em análise', 'warn'], resolved: ['Resolvido', 'ok'], dismissed: ['Descartado', 'grey'] };

  R.load = async () => {
    A.state.reports = (await A.rpc('admin_list_question_reports', { p_status: null })) || [];
    updateCount();
  };

  function updateCount() {
    const open = A.state.reports.filter((r) => r.status === 'open').length;
    $('reportCount').hidden = !open;
    $('reportCount').textContent = open;
  }

  R.render = () => {
    const status = $('rStatus').value;
    const items = A.state.reports.filter((r) =>
      (status === 'active' ? ['open', 'in_review'].includes(r.status) : !status || r.status === status)
      && (!worksheetFilter || r.worksheetId === worksheetFilter));
    const ws = worksheetFilter && A.state.worksheets.find((w) => w.id === worksheetFilter);
    $('rFilterInfo').innerHTML = worksheetFilter
      ? `<div class="row" style="margin-bottom:12px"><span class="badge">Ficha: ${esc(ws ? ws.title : worksheetFilter)}</span><button class="ghost" data-act="clear-filter">✕ Mostrar todas</button></div>` : '';
    if (!items.length) { $('reportList').innerHTML = '<div class="empty">Não há relatos neste filtro. 🎉</div>'; return; }
    $('reportList').innerHTML = items.map((r) => {
      const [sLabel, sKind] = statusLabel[r.status] || [r.status, 'grey'];
      const q = r.question || {};
      const actions = [
        r.status === 'open' ? `<button class="sm secondary" data-act="set" data-status="in_review" data-id="${r.id}">Em análise</button>` : '',
        ['open', 'in_review'].includes(r.status) ? `<button class="sm success" data-act="set" data-status="resolved" data-id="${r.id}">Resolvido</button>` : '',
        ['open', 'in_review'].includes(r.status) ? `<button class="sm secondary" data-act="set" data-status="dismissed" data-id="${r.id}">Descartar</button>` : '',
        ['resolved', 'dismissed'].includes(r.status) ? `<button class="sm secondary" data-act="set" data-status="open" data-id="${r.id}">Reabrir</button>` : '',
      ].join('');
      return `<div class="report">
        <div class="head">
          <span class="badge ${sKind}">${sLabel}</span>
          <span class="badge">${esc(reasonLabel[r.reason] || r.reason)}</span>
          ${r.sameQuestionCount > 1 ? `<span class="badge warn" title="Relatos sobre esta mesma pergunta e versão">${r.sameQuestionCount} relatos nesta pergunta</span>` : ''}
          <span class="spacer"></span><span class="muted small">${A.fmtDate(r.createdAt)}</span>
        </div>
        <div><b>${esc(r.worksheetTitle)}</b> <span class="muted small">• ${esc(r.subjectName)} • ${r.schoolYear}.º Ano • v${r.versionNumber}${r.isLatestVersion ? '' : ' (já existe versão mais recente)'}</span></div>
        <blockquote>${esc(r.message)}</blockquote>
        <div class="question">
          <div class="small muted" style="margin-bottom:4px">Pergunta ${r.questionNumber || '?'} • ${esc(A.typeLabel[q.type] || q.type || '')} • <code>${esc(r.questionId)}</code></div>
          ${r.question ? A.renderQuestionBody(q) : '<i>Pergunta não encontrada nesta versão.</i>'}
        </div>
        <div class="row mt">
          <button class="sm" data-act="open" data-ws="${r.worksheetId}" data-q="${esc(r.questionId)}">Abrir ficha e corrigir</button>
          <span class="spacer"></span>${actions}
        </div>
      </div>`;
    }).join('');
  };

  R.showForWorksheet = (id) => {
    worksheetFilter = id;
    $('rStatus').value = 'active';
    A.app.showTab('reports');
  };

  async function setStatus(id, status) {
    try {
      await A.rpc('admin_set_question_report_status', { p_id: id, p_status: status });
      const r = A.state.reports.find((x) => x.id === id);
      if (r) r.status = status;
      updateCount(); R.render();
      A.toast('ok', `Relato marcado como «${statusLabel[status][0].toLowerCase()}».`);
      A.loadWorksheets().then(() => A.worksheets.render()).catch(() => {});
    } catch (e) { A.fail(e); }
  }

  R.init = () => {
    $('rStatus').addEventListener('input', R.render);
    $('tab-reports').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      if (btn.dataset.act === 'set') setStatus(btn.dataset.id, btn.dataset.status);
      if (btn.dataset.act === 'clear-filter') { worksheetFilter = null; R.render(); }
      if (btn.dataset.act === 'open') {
        // Os ids das perguntas mantêm-se entre versões: destaca a pergunta se ainda existir na versão atual.
        A.editor.open(btn.dataset.ws, { focusQuestionId: btn.dataset.q });
      }
    });
  };
})();
