// Documentos legais: Termos de Utilização e Política de Privacidade, versionados.
// Cada publicação cria uma versão nova e imutável; não há edição nem remoção.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const L = A.legal = {};
  const kindLabel = { terms: 'Termos de Utilização', privacy: 'Política de Privacidade' };
  const errors = {
    INVALID_KIND: 'Tipo de documento inválido.',
    INVALID_TITLE: 'Título inválido (1 a 160 caracteres).',
    INVALID_CONTENT: 'O conteúdo não pode ficar vazio (máx. 200 000 caracteres).',
    INVALID_SUMMARY: 'O resumo das alterações é demasiado longo (máx. 2000 caracteres).',
    UNCHANGED: 'O título e o conteúdo são iguais aos da versão em vigor: não há nada para publicar.',
  };
  let docs = [];
  let missingMigration = false;

  // Sem a migração, o resto da ferramenta continua a funcionar.
  L.load = async () => {
    try { docs = (await A.rpc('admin_list_legal_documents')) || []; missingMigration = false; }
    catch (e) { if (e.code !== 'MIGRATION_MISSING') throw e; docs = []; missingMigration = true; }
  };

  // Mesmo subconjunto de Markdown que a app (LegalMarkdown): #, ##, ###, listas e **negrito**.
  L.renderMarkdown = (src) => {
    const inline = (t) => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    const out = []; let para = []; let list = [];
    const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para = []; } };
    const flushList = () => { if (list.length) { out.push(`<ul>${list.map((i) => `<li>${inline(i)}</li>`).join('')}</ul>`); list = []; } };
    const flush = () => { flushPara(); flushList(); };
    for (const raw of String(src || '').replace(/\r\n/g, '\n').split('\n')) {
      const line = raw.trimEnd(); let m;
      if (!line.trim()) flush();
      else if ((m = /^(#{1,3})\s+(.*)$/.exec(line))) { flush(); out.push(`<h${m[1].length + 2}>${inline(m[2])}</h${m[1].length + 2}>`); }
      else if ((m = /^\s*[-*]\s+(.*)$/.exec(line))) { flushPara(); list.push(m[1]); }
      else { flushList(); para.push(line.trim()); }
    }
    flush();
    return out.join('');
  };

  const current = (kind) => docs.find((d) => d.kind === kind && d.isCurrent);

  L.render = () => {
    const rows = docs.map((d) => `<tr>
        <td>${esc(kindLabel[d.kind] || d.kind)}</td>
        <td>v${d.version} ${d.isCurrent ? '<span class="badge ok">Em vigor</span>' : ''}</td>
        <td>${esc(d.title)}</td>
        <td>${d.requiresReacceptance ? '<span class="badge warn">Exige aceite</span>' : '<span class="badge grey">Sem novo aceite</span>'}</td>
        <td>${A.fmtDate(d.publishedAt)}</td>
        <td>${d.acceptanceCount}</td>
        <td class="actions"><button class="sm secondary" data-act="view" data-id="${d.id}">Ver</button>
          <button class="sm secondary" data-act="copy" data-id="${d.id}">Nova versão a partir desta</button></td>
      </tr>`).join('');
    $('legalRows').innerHTML = rows || '<tr><td colspan="7" class="empty">Ainda não há documentos publicados. Sem as duas versões publicadas, a app não permite criar contas.</td></tr>';
    const missing = Object.keys(kindLabel).filter((k) => !current(k));
    $('legalWarn').innerHTML = missingMigration
      ? A.msg('err', 'Aplica a migração <code>202611060006_legal_documents.sql</code> para gerir os documentos legais.')
      : missing.length
      ? A.msg('warn', `Falta publicar: <b>${missing.map((k) => esc(kindLabel[k])).join(', ')}</b>. Enquanto faltar, o registo de novas contas está bloqueado na app.`) : '';
    preview();
  };

  function preview() {
    $('lPreview').innerHTML = L.renderMarkdown($('lContent').value) || '<p class="muted">A pré-visualização aparece aqui.</p>';
  }

  function fillFrom(doc) {
    $('lKind').value = doc.kind;
    $('lTitle').value = doc.title;
    $('lContent').value = doc.content;
    $('lSummary').value = '';
    $('lReaccept').checked = true;
    preview();
    $('lKind').scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  async function publish() {
    const kind = $('lKind').value, title = $('lTitle').value.trim(), content = $('lContent').value;
    const summary = $('lSummary').value.trim(), reaccept = $('lReaccept').checked;
    const last = current(kind);
    if (last && !summary) { A.toast('warn', 'Indica o resumo das alterações: é mostrado aos responsáveis.'); $('lSummary').focus(); return; }
    const consequence = !last
      ? 'É a primeira versão: todos os responsáveis terão de a aceitar.'
      : reaccept
        ? `Todos os responsáveis terão de aceitar a v${last.version + 1} no próximo acesso.`
        : `Correção menor: quem aceitou a v${last.version} ou anterior válida não precisa de voltar a aceitar.`;
    if (!confirm(`Publicar ${kindLabel[kind]} v${(last?.version || 0) + 1}?\n\n${consequence}\n\nAs versões publicadas não podem ser alteradas nem apagadas.`)) return;
    $('lPublish').disabled = true;
    try {
      const doc = await A.rpc('admin_publish_legal_document', {
        p_kind: kind, p_title: title, p_content: content, p_change_summary: summary || null, p_requires_reacceptance: reaccept,
      });
      A.toast('ok', `${esc(kindLabel[kind])} v${doc.version} publicada.`);
      $('lSummary').value = '';
      await L.load(); L.render();
    } catch (e) {
      A.fail(e.code && errors[e.code] ? new Error(errors[e.code]) : e);
    } finally { $('lPublish').disabled = false; }
  }

  L.init = () => {
    $('lContent').addEventListener('input', preview);
    $('lFile').addEventListener('change', async () => {
      const file = $('lFile').files[0];
      if (!file) return;
      $('lContent').value = await file.text();
      const heading = /^#\s+(.+)$/m.exec($('lContent').value);
      if (heading && !$('lTitle').value.trim()) $('lTitle').value = heading[1].trim();
      $('lFile').value = '';
      preview();
    });
    $('lPublish').addEventListener('click', publish);
    $('tab-legal').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      const doc = docs.find((d) => d.id === btn.dataset.id);
      if (!doc) return;
      if (btn.dataset.act === 'copy') fillFrom(doc);
      if (btn.dataset.act === 'view') A.dialog({
        title: `${kindLabel[doc.kind]} v${doc.version}`, ok: 'Fechar', info: true,
        body: `<p class="hint">Publicada em ${A.fmtDate(doc.publishedAt)} • ${doc.acceptanceCount} aceites • SHA-256 <code>${esc(doc.contentSha256.slice(0, 16))}…</code></p>
          ${doc.changeSummary ? A.msg('info', '<b>O que mudou:</b> ' + esc(doc.changeSummary)) : ''}
          <div class="legal-preview">${L.renderMarkdown(doc.content)}</div>`,
      });
    });
  };
})();
