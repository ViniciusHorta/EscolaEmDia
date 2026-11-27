// Cobertura do catálogo: matriz curricular do ensino básico (1.º ao 3.º ciclo) › temas › conteúdos,
// cruzada com as fichas publicadas. Meta: pelo menos MIN_FREE fichas Free e MIN_PREMIUM Premium por conteúdo.
// Os conteúdos (tabela topic_contents) são só do admin; os responsáveis veem apenas os temas.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const C = A.coverage = {};

  C.MIN_FREE = 1;
  C.MIN_PREMIUM = 3;

  // Matriz curricular (Decreto-Lei n.º 55/2018, anexos I a III).
  // «fichas: false» = disciplina da matriz que não se trabalha com fichas (listada, sem metas).
  // «aliases» = outros nomes com que a disciplina pode estar gravada na base.
  C.CURRICULUM = [
    { cycle: '1.º Ciclo', years: [1, 2, 3, 4], subjects: [
      { name: 'Português', years: [1, 2, 3, 4], fichas: true },
      { name: 'Matemática', years: [1, 2, 3, 4], fichas: true },
      { name: 'Estudo do Meio', years: [1, 2, 3, 4], fichas: true },
      { name: 'Inglês', years: [3, 4], fichas: true },
      { name: 'Cidadania e Desenvolvimento', years: [1, 2, 3, 4], fichas: false },
      { name: 'Educação Artística', years: [1, 2, 3, 4], fichas: false },
      { name: 'Educação Física', years: [1, 2, 3, 4], fichas: false },
      { name: 'TIC', years: [1, 2, 3, 4], fichas: false },
    ] },
    { cycle: '2.º Ciclo', years: [5, 6], subjects: [
      { name: 'Português', years: [5, 6], fichas: true },
      { name: 'Inglês', years: [5, 6], fichas: true },
      { name: 'História e Geografia de Portugal', aliases: ['HGP'], years: [5, 6], fichas: true },
      { name: 'Matemática', years: [5, 6], fichas: true },
      { name: 'Ciências Naturais', aliases: ['Ciências'], years: [5, 6], fichas: true },
      { name: 'Cidadania e Desenvolvimento', years: [5, 6], fichas: false },
      { name: 'Educação Visual', years: [5, 6], fichas: false },
      { name: 'Educação Tecnológica', years: [5, 6], fichas: false },
      { name: 'Educação Musical', years: [5, 6], fichas: false },
      { name: 'Educação Física', years: [5, 6], fichas: false },
      { name: 'TIC', years: [5, 6], fichas: false },
    ] },
    { cycle: '3.º Ciclo', years: [7, 8, 9], subjects: [
      { name: 'Português', years: [7, 8, 9], fichas: true },
      { name: 'Inglês', years: [7, 8, 9], fichas: true },
      { name: 'Francês', note: 'Língua Estrangeira II (opção)', years: [7, 8, 9], fichas: true },
      { name: 'Espanhol', note: 'Língua Estrangeira II (opção)', years: [7, 8, 9], fichas: true },
      { name: 'História', years: [7, 8, 9], fichas: true },
      { name: 'Geografia', years: [7, 8, 9], fichas: true },
      { name: 'Matemática', years: [7, 8, 9], fichas: true },
      { name: 'Ciências Naturais', aliases: ['Ciências'], years: [7, 8, 9], fichas: true },
      { name: 'Físico-Química', aliases: ['Ciências Físico-Químicas', 'Física e Química', 'Fisico Quimica'], years: [7, 8, 9], fichas: true },
      { name: 'Cidadania e Desenvolvimento', years: [7, 8, 9], fichas: false },
      { name: 'Educação Visual', years: [7, 8, 9], fichas: false },
      { name: 'Educação Física', years: [7, 8, 9], fichas: false },
      { name: 'TIC', years: [7, 8], fichas: false },
      { name: 'Complemento à Educação Artística', years: [7, 8, 9], fichas: false },
    ] },
  ];

  const key = (s) => A.norm(s).replace(/[^a-z0-9]+/g, ' ').trim();
  let cycleFilter = '', onlyGaps = false, open = null; // open = { subjectId, year }

  function dbSubject(cur) {
    const names = [cur.name, ...(cur.aliases || [])].map(key);
    return A.state.subjects.find((s) => names.includes(key(s.name)));
  }
  const curFor = (subjectId) => C.CURRICULUM.flatMap((c) => c.subjects).find((s) => dbSubject(s)?.id === subjectId);

  // ---------- Cálculo ----------
  const wsById = () => new Map(A.state.worksheets.map((w) => [w.id, w]));
  const isPublished = (w) => w && w.status === 'published';

  function contentStats(c, byId) {
    const ws = c.worksheetIds.map((id) => byId.get(id)).filter(Boolean);
    const pub = ws.filter(isPublished);
    const free = pub.filter((w) => w.accessTier === 'free').length, premium = pub.length - free;
    const missFree = Math.max(0, C.MIN_FREE - free), missPremium = Math.max(0, C.MIN_PREMIUM - premium);
    return { ...c, ws, free, premium, drafts: ws.filter((w) => w.status === 'draft').length,
      missFree, missPremium, missing: missFree + missPremium };
  }

  // Uma célula = disciplina curricular × ano.
  function cells() {
    const byId = wsById(), out = [];
    for (const cyc of C.CURRICULUM) {
      for (const cur of cyc.subjects.filter((s) => s.fichas)) {
        const s = dbSubject(cur);
        for (const year of cur.years) {
          const contents = s ? A.state.contents.filter((c) => c.subjectId === s.id && c.schoolYear === year).map((c) => contentStats(c, byId)) : [];
          const ws = s ? A.state.worksheets.filter((w) => w.subjectId === s.id && w.latest?.schoolYear === year) : [];
          const linked = new Set(contents.flatMap((c) => c.worksheetIds));
          out.push({
            cycle: cyc.cycle, cur, subject: s, year, contents,
            total: contents.length, done: contents.filter((c) => !c.missing).length,
            missFree: contents.reduce((n, c) => n + c.missFree, 0), missPremium: contents.reduce((n, c) => n + c.missPremium, 0),
            published: ws.filter(isPublished).length,
            wsTarget: contents.length * (C.MIN_FREE + C.MIN_PREMIUM),
            wsDone: contents.reduce((n, c) => n + (C.MIN_FREE + C.MIN_PREMIUM - c.missing), 0),
            unlinked: ws.filter((w) => isPublished(w) && !linked.has(w.id)),
          });
        }
      }
    }
    return out;
  }

  const level = (c) => !c.total ? 'none' : c.done === c.total ? 'ok' : c.contents.some((x) => x.free + x.premium) ? 'warn' : 'err';

  // ---------- Matriz ----------
  function cellHtml(c) {
    if (!c) return '<td class="cov-na" title="Não faz parte da matriz neste ano">—</td>';
    const isOpen = open && c.subject && open.subjectId === c.subject.id && open.year === c.year;
    const attrs = c.subject ? `data-cell="1" data-subject="${c.subject.id}" data-year="${c.year}"` : '';
    if (!c.total) {
      return `<td class="cov-cell none ${isOpen ? 'open' : ''}" ${attrs} title="${c.subject ? 'Ainda sem conteúdos registados. Clica para os adicionar.' : 'A disciplina ainda não existe na base'}">
        <span>sem conteúdos</span><span class="cov-d">${c.published} ficha${c.published === 1 ? '' : 's'}</span></td>`;
    }
    return `<td class="cov-cell ${level(c)} ${isOpen ? 'open' : ''}" ${attrs} title="${esc(`${c.cur.name} • ${c.year}.º Ano\n${c.done} de ${c.total} conteúdos com o mínimo\nFaltam ${c.missFree} Free e ${c.missPremium} Premium`)}">
      <span>${c.done}/${c.total} conteúdos</span>
      <span class="cov-d">${c.wsDone}/${c.wsTarget} fichas</span>
      ${c.done < c.total ? `<span class="cov-d">faltam ${c.missFree} F • ${c.missPremium} ★</span>` : '<span class="cov-d">completo ✓</span>'}
      ${c.unlinked.length ? `<span class="cov-d">${c.unlinked.length} sem conteúdo</span>` : ''}
    </td>`;
  }

  function cycleHtml(cyc, all) {
    const mine = all.filter((c) => c.cycle === cyc.cycle);
    const total = mine.reduce((n, c) => n + c.total, 0), done = mine.reduce((n, c) => n + c.done, 0);
    const pct = total ? Math.round((done / total) * 100) : 0;
    const wsTarget = mine.reduce((n, c) => n + c.wsTarget, 0), wsDone = mine.reduce((n, c) => n + c.wsDone, 0);
    const subjects = cyc.subjects.filter((s) => s.fichas)
      .filter((s) => !onlyGaps || mine.some((c) => c.cur === s && (!c.total || c.done < c.total)));
    const out = cyc.subjects.filter((s) => !s.fichas).map((s) => s.name);
    const rows = subjects.map((s) => `<tr>
        <th scope="row">${esc(s.name)}${s.note ? `<div class="muted small">${esc(s.note)}</div>` : ''}
          ${dbSubject(s) ? '' : '<div><span class="badge err" title="Cria a disciplina em Temas com este nome">Disciplina não criada</span></div>'}</th>
        ${cyc.years.map((y) => cellHtml(mine.find((c) => c.cur === s && c.year === y))).join('')}
      </tr>`).join('');
    return `<section>
      <div class="row" style="margin-bottom:10px">
        <h3 style="margin:0">${cyc.cycle}</h3>
        <span class="badge ${!total ? 'grey' : pct === 100 ? 'ok' : pct ? 'warn' : 'err'}">${done}/${total} conteúdos completos • ${pct}%</span>
        ${wsTarget ? `<span class="badge grey">${wsDone}/${wsTarget} fichas feitas • ${Math.round((wsDone / wsTarget) * 100)}%</span>` : ''}
      </div>
      <div class="cov-bar"><span style="width:${pct}%"></span></div>
      ${rows ? `<div style="overflow-x:auto"><table class="tbl cov-tbl">
        <thead><tr><th>Disciplina</th>${cyc.years.map((y) => `<th>${y}.º Ano</th>`).join('')}</tr></thead>
        <tbody>${rows}</tbody></table></div>` : '<div class="empty">Tudo completo neste ciclo. 🎉</div>'}
      ${out.length ? `<p class="hint" style="margin:10px 0 0">Também na matriz (sem metas de fichas): ${out.map(esc).join(', ')}.</p>` : ''}
    </section>`;
  }

  // ---------- Detalhe de uma disciplina × ano ----------
  const semLabel = (s) => s ? `${s}.º S` : '—';
  const countBadge = (n, min, kind) => `<span class="badge ${n >= min ? 'ok' : n ? 'warn' : 'err'}">${kind === 'free' ? 'F' : '★'} ${n}/${min}</span>`;

  function detailHtml(all) {
    if (!open) return '';
    const cell = all.find((c) => c.subject?.id === open.subjectId && c.year === open.year);
    const subject = A.subject(open.subjectId);
    if (!subject) return '';
    const contents = cell ? cell.contents : [];
    const topics = A.state.topics.filter((t) => t.subjectId === subject.id && t.schoolYear === open.year
        && (!t.archivedAt || contents.some((c) => c.topicId === t.id)))
      .sort((a, b) => a.name.localeCompare(b.name, 'pt'));
    const draft = draftFor(subject.id, open.year);
    const draftCount = draft ? Object.values(draft).reduce((n, l) => n + l.length, 0) : 0;
    const blocks = topics.map((t) => {
      const list = contents.filter((c) => c.topicId === t.id)
        .sort((a, b) => (a.semester || 9) - (b.semester || 9) || a.position - b.position || a.name.localeCompare(b.name, 'pt'));
      return `<tr class="group"><td colspan="5">${esc(t.name)} <span class="muted small">(${list.length})</span>
          <button class="sm ghost" data-act="add" data-topic="${t.id}">+ conteúdo</button></td></tr>` +
        (list.length ? list.map((c) => `<tr>
          <td>${esc(c.name)}</td>
          <td class="small muted">${semLabel(c.semester)}</td>
          <td>${countBadge(c.free, C.MIN_FREE, 'free')} ${countBadge(c.premium, C.MIN_PREMIUM, 'premium')}${c.drafts ? ` <span class="badge grey">+${c.drafts} rasc.</span>` : ''}</td>
          <td class="small">${c.ws.map((w) => `<a href="#" data-act="edit-ws" data-id="${w.id}" class="${isPublished(w) ? '' : 'muted'}">${esc(w.title)}</a>`).join(', ') || '<span class="muted">—</span>'}</td>
          <td class="actions"><button class="sm ${c.missing ? '' : 'secondary'}" data-act="new-ws" data-id="${c.id}" title="Criar uma ficha para este conteúdo">+ Ficha</button>
            <button class="sm secondary" data-act="ai" data-id="${c.id}" title="Gerar fichas com IA (Gemini)">✨ IA</button>
            <button class="icon" data-act="edit" data-id="${c.id}" title="Editar">✎</button><button class="icon" data-act="del" data-id="${c.id}" title="Apagar">🗑</button></td>
        </tr>`).join('') : '<tr><td colspan="5" class="muted small">Sem conteúdos neste tema.</td></tr>');
    }).join('');
    const unlinked = cell ? cell.unlinked : [];
    return `<section class="cov-detail">
      <div class="row" style="margin-bottom:8px">
        <h3 style="margin:0">${esc(subject.name)} • ${open.year}.º Ano</h3>
        ${cell && cell.total ? `<span class="badge ${level(cell) === 'ok' ? 'ok' : 'warn'}">${cell.done}/${cell.total} conteúdos completos</span>
          <span class="badge grey">${cell.wsDone}/${cell.wsTarget} fichas feitas</span>` : ''}
        <span class="spacer"></span>
        <button class="sm secondary" data-act="list">Ver fichas</button>
        <button class="sm secondary" data-act="paste">📋 Colar lista</button>
        ${draftCount ? `<button class="sm secondary" data-act="draft">Importar rascunho (${draftCount})</button>` : ''}
        <button class="sm" data-act="add">+ Conteúdo</button>
        <button class="sm ghost" data-act="close">✕</button>
      </div>
      ${A.state.contentsMissing ? A.msg('warn', 'Aplica a migração <code>202611210001_topic_contents.sql</code> para registar conteúdos.') : ''}
      ${unlinked.length ? A.msg('warn', `<b>${unlinked.length} ficha(s) publicada(s) sem conteúdo marcado</b> (não contam para a cobertura): ${unlinked.map((w) => `<a href="#" data-act="edit-ws" data-id="${w.id}">${esc(w.title)}</a>`).join(', ')}. Abre-as e marca os conteúdos.`) : ''}
      ${A.aiGen.panelHtml(open)}
      ${topics.length ? `<div style="overflow-x:auto"><table class="tbl">
        <thead><tr><th>Conteúdo</th><th>Sem.</th><th>Fichas publicadas</th><th>Fichas ligadas</th><th></th></tr></thead>
        <tbody>${blocks}</tbody></table></div>`
        : '<div class="empty">Ainda não há temas nem conteúdos. Usa «Colar lista» com o documento das educadoras' + (draftCount ? ' ou «Importar rascunho»' : '') + '.</div>'}
    </section>`;
  }

  // ---------- Prioridades ----------
  function todoHtml(all) {
    const scoped = all.filter((c) => !cycleFilter || c.cycle === cycleFilter);
    const gaps = scoped.flatMap((c) => c.contents.filter((x) => x.missing).map((x) => ({ ...x, cell: c })))
      // Primeiro sem nenhuma Free (o plano gratuito não tem nada), depois 1.º semestre, depois por ano.
      .sort((a, b) => (b.missFree - a.missFree) || ((a.semester || 9) - (b.semester || 9)) || (a.schoolYear - b.schoolYear)
        || (b.missing - a.missing) || a.name.localeCompare(b.name, 'pt'));
    const empty = scoped.filter((c) => c.subject && !c.total);
    if (!gaps.length && !empty.length) return '';
    const rows = gaps.slice(0, 50).map((x) => `<tr>
      <td>${x.schoolYear}.º</td>
      <td><b>${esc(x.cell.cur.name)}</b> <span class="muted small">› ${esc(A.topic(x.topicId)?.name || '')}</span><div>${esc(x.name)}</div></td>
      <td class="small muted">${semLabel(x.semester)}</td>
      <td>${x.missFree ? `<span class="badge ok">+${x.missFree} Free</span>` : ''} ${x.missPremium ? `<span class="badge premium">+${x.missPremium} Premium</span>` : ''}</td>
      <td class="actions"><button class="sm" data-act="new-ws" data-id="${x.id}">+ Ficha</button>
        <button class="sm secondary" data-cell="1" data-subject="${x.subjectId}" data-year="${x.schoolYear}">Abrir</button></td>
    </tr>`).join('');
    return `<div class="page-head"><h2>O que criar a seguir</h2><span class="badge grey">${gaps.length} conteúdos</span></div>
      <p class="hint">Primeiro os conteúdos sem nenhuma ficha Free (o plano gratuito não tem nada), depois os do 1.º semestre e por ano.</p>
      ${empty.length ? A.msg('info', `<b>${empty.length} disciplina(s) × ano ainda sem conteúdos registados</b>: ${empty.slice(0, 12).map((c) => `<a href="#" data-cell="1" data-subject="${c.subject.id}" data-year="${c.year}">${esc(c.cur.name)} ${c.year}.º</a>`).join(', ')}${empty.length > 12 ? '…' : ''}`) : ''}
      ${gaps.length ? `<section><div style="overflow-x:auto"><table class="tbl">
        <thead><tr><th>Ano</th><th>Conteúdo</th><th>Sem.</th><th>Falta</th><th></th></tr></thead>
        <tbody>${rows}</tbody></table></div>
        ${gaps.length > 50 ? `<p class="hint" style="margin:10px 0 0">E mais ${gaps.length - 50}. Filtra por ciclo para ver o resto.</p>` : ''}</section>` : ''}`;
  }

  function extrasHtml() {
    const known = new Set(C.CURRICULUM.flatMap((c) => c.subjects).map((s) => dbSubject(s)?.id).filter(Boolean));
    const extras = A.state.subjects.filter((s) => !known.has(s.id));
    if (!extras.length) return '';
    return A.msg('info', `Disciplinas na base fora da matriz (não contam para a cobertura): ${extras.map((s) => `<b>${esc(s.name)}</b>`).join(', ')}.
      Se for o mesmo que uma disciplina da matriz com outro nome, acrescenta-o aos <code>aliases</code> em <code>js/coverage.js</code>.`);
  }

  // Para as rotas: célula aberta ({ subjectId, year }) ou null.
  C.current = () => open;
  C.setOpen = (o) => { open = o && A.subject(o.subjectId) ? o : null; C.render(); };

  C.render = () => {
    if (!$('covStats')) return;
    const all = cells();
    const scoped = all.filter((c) => !cycleFilter || c.cycle === cycleFilter);
    const sum = (f) => scoped.reduce((n, c) => n + f(c), 0);
    const wsT = sum((c) => c.wsTarget), wsD = sum((c) => c.wsDone);
    $('covStats').innerHTML = `<div class="stats">
      <div class="stat"><b>${wsD}/${wsT}</b><span>fichas feitas${wsT ? ` • ${Math.round((wsD / wsT) * 100)}%` : ''}</span></div>
      <div class="stat"><b>${sum((c) => c.done)}/${sum((c) => c.total)}</b><span>conteúdos completos</span></div>
      <div class="stat"><b>${sum((c) => c.contents.filter((x) => !x.free && !x.premium).length)}</b><span>conteúdos sem nenhuma ficha</span></div>
      <div class="stat"><b>${sum((c) => c.missFree)}</b><span>fichas Free em falta</span></div>
      <div class="stat"><b>${sum((c) => c.missPremium)}</b><span>fichas Premium em falta</span></div>
      <div class="stat"><b>${scoped.filter((c) => c.subject && !c.total).length}</b><span>disciplina × ano sem conteúdos</span></div>
      <div class="stat"><b>${sum((c) => c.unlinked.length)}</b><span>fichas sem conteúdo marcado</span></div>
    </div>`;
    $('covExtras').innerHTML = extrasHtml();
    $('covDetail').innerHTML = detailHtml(all);
    $('covMatrix').innerHTML = C.CURRICULUM.filter((c) => !cycleFilter || c.cycle === cycleFilter).map((c) => cycleHtml(c, all)).join('');
    $('covTodo').innerHTML = todoHtml(all);
  };

  // ---------- Ações ----------
  async function reload() {
    try { await Promise.all([A.loadCatalogue(), A.loadContents()]); } catch (e) { A.fail(e); }
    C.render(); A.topics.render();
  }

  const topicSelect = (selected, { allowNew = true } = {}) => {
    const ts = A.topicsFor(open.subjectId, open.year);
    return `<select name="topic">${ts.map((t) => `<option value="${t.id}" ${t.id === selected ? 'selected' : ''}>${esc(t.name)}</option>`).join('')}
      ${allowNew ? `<option value="__new" ${ts.length ? '' : 'selected'}>+ Novo tema…</option>` : ''}</select>`;
  };
  const semSelect = (v) => `<select name="semester"><option value="">Sem semestre</option>
    <option value="1" ${v === 1 ? 'selected' : ''}>1.º semestre</option><option value="2" ${v === 2 ? 'selected' : ''}>2.º semestre</option></select>`;
  const newTopicField = '<div class="field" data-newtopic><label>Nome do novo tema</label><input name="newTopic" maxlength="120" placeholder="Ex.: Números e operações"></div>';
  // Mostra o campo «novo tema» só quando essa opção está escolhida.
  function wireNewTopic() {
    const sel = $('dlgBody').querySelector('select[name=topic]'), box = $('dlgBody').querySelector('[data-newtopic]');
    if (!sel || !box) return;
    const sync = () => { box.hidden = sel.value !== '__new'; };
    sel.addEventListener('input', sync); sync();
  }
  // Tema escolhido no formulário: { topicId } ou { topicName } (a criar).
  function topicFrom(form) {
    if (form.topic.value !== '__new') return { topicId: form.topic.value };
    const name = form.newTopic.value.trim();
    if (!name) throw new Error('Indica o nome do novo tema.');
    return { topicName: name };
  }

  async function editContent(id, topicId) {
    const c = id ? A.state.contents.find((x) => x.id === id) : null;
    const p = A.dialog({
      title: c ? 'Editar conteúdo' : 'Novo conteúdo',
      body: `<div class="field"><label>Tema</label>${topicSelect(c ? c.topicId : topicId, { allowNew: !c })}</div>${c ? '' : newTopicField}
        <div class="field"><label>Conteúdo</label><input name="cname" maxlength="200" value="${esc(c ? c.name : '')}" placeholder="Ex.: Valor posicional"></div>
        <div class="field"><label>Semestre</label>${semSelect(c ? c.semester : null)}</div>`,
      onSubmit: async (form) => {
        const name = form.cname.value.trim(), semester = Number(form.semester.value) || null;
        const t = topicFrom(form);
        if (t.topicName) {
          await A.rpc('admin_import_contents', { p_items: [{ subjectId: open.subjectId, schoolYear: open.year, topicName: t.topicName, name, semester }] });
        } else {
          await A.rpc('admin_save_content', { p_id: id || null, p_topic_id: t.topicId, p_name: name, p_semester: semester });
        }
      },
    });
    wireNewTopic();
    if (await p) { await reload(); A.toast('ok', c ? 'Conteúdo atualizado.' : 'Conteúdo criado.'); }
  }

  async function deleteContent(id) {
    const c = A.state.contents.find((x) => x.id === id);
    if (!c) return;
    const n = c.worksheetIds.length;
    if (!confirm(`Apagar o conteúdo «${c.name}»?${n ? `\n\n${n} ficha(s) deixam de estar marcadas com ele (as fichas não mudam).` : ''}`)) return;
    try { await A.rpc('admin_delete_content', { p_id: id }); await reload(); A.toast('ok', 'Conteúdo apagado.'); }
    catch (e) { A.fail(e); }
  }

  // Lista colada (ex.: «Tópicos de estudo» das educadoras). Uma linha por conteúdo;
  // uma linha que acaba em «:» muda o tema das linhas seguintes.
  C.parseList = (text) => {
    const out = [];
    let topic = null;
    for (const raw of String(text).split(/\r?\n/)) {
      const line = raw.replace(/^\s*(?:[-–•*·▪◦]|\d+[.)])\s*/, '').replace(/\s+/g, ' ').trim();
      if (!line) continue;
      if (/:$/.test(line)) { topic = line.slice(0, -1).trim(); continue; }
      const name = line.replace(/[.;]+$/, '').trim();
      if (name) out.push({ topic, name });
    }
    return out;
  };

  async function pasteList() {
    const p = A.dialog({
      title: `Colar lista • ${A.subject(open.subjectId)?.name} ${open.year}.º Ano`,
      ok: 'Importar',
      body: `<p class="hint">Uma linha por conteúdo (como no documento das educadoras). Para mudar de tema a meio, escreve uma linha com o nome do tema seguido de «:».
          Conteúdos que já existam no tema são ignorados.</p>
        <div class="field"><textarea name="list" rows="10" placeholder="Valor posicional.\nMultiplicação – estratégias de cálculo.\nGeometria:\nSólidos – planificações."></textarea></div>
        <div class="field"><label>Tema (para as linhas sem tema)</label>${topicSelect(null)}</div>${newTopicField}
        <div class="field"><label>Semestre</label>${semSelect(null)}</div>`,
      onSubmit: async (form) => {
        const lines = C.parseList(form.list.value);
        if (!lines.length) throw new Error('A lista está vazia.');
        const semester = Number(form.semester.value) || null;
        const needDefault = lines.some((l) => !l.topic);
        const def = needDefault ? topicFrom(form) : {};
        const items = lines.map((l) => ({ subjectId: open.subjectId, schoolYear: open.year, name: l.name, semester,
          ...(l.topic ? { topicName: matchTopic(l.topic)?.name || l.topic } : def) }));
        return A.rpc('admin_import_contents', { p_items: items });
      },
    });
    wireNewTopic();
    const r = await p;
    if (r && r !== true) { await reload(); A.toast('ok', importText(r)); }
  }

  const importText = (r) => `${r.contentsCreated} conteúdo(s) criados${r.topicsCreated ? `, ${r.topicsCreated} tema(s) novo(s)` : ''}${r.skipped ? `, ${r.skipped} já existiam` : ''}.`;
  const matchTopic = (name) => A.topicsFor(open.subjectId, open.year).find((t) => key(t.name) === key(name));

  function draftFor(subjectId, year) {
    const cur = curFor(subjectId), d = cur && A.CURRICULUM_DRAFT && A.CURRICULUM_DRAFT[cur.name];
    return d && d[year];
  }

  // Rascunho da grade: para cada tema do rascunho, escolher um tema existente ou criar um novo.
  async function importDraft() {
    const draft = draftFor(open.subjectId, open.year);
    if (!draft) return;
    const ts = A.topicsFor(open.subjectId, open.year);
    const existing = new Set(A.state.contents.filter((c) => c.subjectId === open.subjectId && c.schoolYear === open.year).map((c) => key(c.name)));
    const rows = Object.entries(draft).map(([tname, list], i) => {
      const match = matchTopic(tname);
      const fresh = list.filter((n) => !existing.has(key(n)));
      return `<div class="field cov-draft">
        <label><input type="checkbox" name="on${i}" ${fresh.length ? 'checked' : ''} style="width:auto"> ${esc(tname)} <span class="muted small">(${fresh.length} novo(s) de ${list.length})</span></label>
        <select name="t${i}"><option value="__new" ${match ? '' : 'selected'}>Criar tema «${esc(tname)}»</option>
          ${ts.map((t) => `<option value="${t.id}" ${match?.id === t.id ? 'selected' : ''}>Usar tema existente: ${esc(t.name)}</option>`).join('')}</select>
        <details><summary class="small">Ver conteúdos</summary><ul class="small">${list.map((n) => `<li class="${existing.has(key(n)) ? 'muted' : ''}">${esc(n)}${existing.has(key(n)) ? ' (já existe)' : ''}</li>`).join('')}</ul></details>
      </div>`;
    }).join('');
    const r = await A.dialog({
      title: `Importar rascunho • ${A.subject(open.subjectId)?.name} ${open.year}.º Ano`,
      ok: 'Importar',
      body: `<p class="hint">Rascunho com base nas Aprendizagens Essenciais: revê antes de importar. Reutiliza os temas que já existem sempre que fizer sentido,
          para não criar temas parecidos. Temas novos só aparecem aos responsáveis quando tiverem fichas publicadas.</p>${rows}`,
      onSubmit: async (form) => {
        const items = [];
        Object.entries(draft).forEach(([tname, list], i) => {
          if (!form[`on${i}`].checked) return;
          const v = form[`t${i}`].value;
          const t = v === '__new' ? { topicName: tname } : { topicId: v };
          list.forEach((name) => items.push({ subjectId: open.subjectId, schoolYear: open.year, name, ...t }));
        });
        if (!items.length) throw new Error('Nenhum tema escolhido.');
        return A.rpc('admin_import_contents', { p_items: items });
      },
    });
    if (r && r !== true) { await reload(); A.toast('ok', importText(r)); }
  }

  // Próximo título livre: «‹conteúdo› - 01», «- 02», … (na mesma disciplina e ano).
  C.nextTitle = (name, subjectId, year) => {
    const base = key(name), used = new Set();
    for (const w of A.state.worksheets) {
      if (w.subjectId !== subjectId || w.latest?.schoolYear !== year) continue;
      const m = key(w.title).match(/^(.*) (\d+)$/);
      if (m && m[1] === base) used.add(Number(m[2]));
    }
    let n = 1;
    while (used.has(n)) n++;
    return `${name} - ${String(n).padStart(2, '0')}`;
  };

  // Nova ficha pré-preenchida para um conteúdo; Free se ainda faltar a Free desse conteúdo.
  function newWorksheet(contentId) {
    const c = A.state.contents.find((x) => x.id === contentId);
    if (!c) return;
    const byId = wsById(), st = contentStats(c, byId);
    if (!open || open.subjectId !== c.subjectId || open.year !== c.schoolYear) { open = { subjectId: c.subjectId, year: c.schoolYear }; A.app.sync(); }
    // O router abre o editor a partir do endereço (assim um recarregar mantém tudo preenchido).
    const q = new URLSearchParams({ disciplina: c.subjectId, ano: c.schoolYear, tema: c.topicId, conteudo: c.id,
      titulo: C.nextTitle(c.name, c.subjectId, c.schoolYear), tipo: st.missFree ? 'free' : 'premium', voltar: 'cobertura' });
    location.hash = `#/fichas/nova?${q}`;
  }

  function openList() {
    A.app.showTab('worksheets');
    A.worksheets.closeEditor();
    $('fSearch').value = ''; $('fStatus').value = ''; $('fTopic').value = '';
    $('fSubject').value = open.subjectId; $('fYear').value = String(open.year);
    A.worksheets.render();
  }

  C.init = () => {
    $('covCycle').innerHTML = '<option value="">Todos os ciclos</option>' +
      C.CURRICULUM.map((c) => `<option value="${c.cycle}">${c.cycle}</option>`).join('');
    $('covCycle').addEventListener('input', (e) => { cycleFilter = e.target.value; C.render(); });
    $('covGaps').addEventListener('change', (e) => { onlyGaps = e.target.checked; C.render(); });
    $('covMin').textContent = `Meta por conteúdo: ${C.MIN_FREE} Free e ${C.MIN_PREMIUM} Premium publicadas`;
    $('tab-coverage').addEventListener('click', (ev) => {
      const cell = ev.target.closest('[data-cell]');
      if (cell) {
        ev.preventDefault();
        const same = open && open.subjectId === cell.dataset.subject && open.year === Number(cell.dataset.year);
        open = same && cell.tagName === 'TD' ? null : { subjectId: cell.dataset.subject, year: Number(cell.dataset.year) };
        C.render(); A.app.sync();
        if (open) $('covDetail').scrollIntoView({ behavior: 'smooth', block: 'start' });
        return;
      }
      if (ev.target.closest('[data-ai-clear]')) { A.aiGen.clear(open); return; }
      const el = ev.target.closest('[data-act]');
      if (el && el.dataset.act === 'new-ws') { ev.preventDefault(); newWorksheet(el.dataset.id); return; }
      if (!el || !open) return;
      ev.preventDefault();
      ({
        add: () => editContent(null, el.dataset.topic),
        edit: () => editContent(el.dataset.id),
        del: () => deleteContent(el.dataset.id),
        paste: pasteList,
        draft: importDraft,
        list: openList,
        close: () => { open = null; C.render(); A.app.sync(); },
        'edit-ws': () => A.editor.open(el.dataset.id),
        ai: () => A.aiGen.open(el.dataset.id),
      })[el.dataset.act]?.();
    });
  };
})();
