// Arranque: ligação ao Supabase, separadores e recarregamento de dados.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const app = A.app = {};

  async function connect() {
    const box = $('connMsg');
    const url = $('url').value.trim().replace(/\/+$/, ''), key = $('key').value.trim();
    if (!url || !key) { box.innerHTML = A.msg('err', 'Indica o URL do projeto e a chave service_role.'); return; }
    A.state.url = url; A.state.key = key;
    box.innerHTML = A.msg('warn', 'A ligar…');
    $('connect').disabled = true;
    try {
      await Promise.all([A.loadCatalogue(), A.loadWorksheets(), A.loadContents(), A.reports.load(), A.legal.load()]);
      // Secções que dependem de migrações mais recentes não impedem a ligação (mostram o erro na própria secção).
      await A.users.load();
      $('key').value = '';
      box.innerHTML = '';
      $('loginView').hidden = true;
      $('appView').hidden = false;
      $('connLabel').textContent = new URL(url).hostname.split('.')[0];
      renderAll();
      // Volta à página do endereço (ex.: depois de recarregar e voltar a ligar).
      await navigate();
    } catch (e) {
      A.state.key = '';
      box.innerHTML = A.msg('err', 'Não foi possível ligar: ' + esc(e.message) +
        (e.code === 'MIGRATION_MISSING' ? '' : '<br>Confirma o URL e que usas a chave <b>service_role legacy (JWT)</b>.'));
    } finally { $('connect').disabled = false; }
  }

  function logout() {
    if (A.editor.isDirty() && !confirm('Há alterações por gravar. Sair mesmo assim?')) return;
    // Recarregar descarta a chave e todo o estado em memória.
    window.removeEventListener('beforeunload', beforeUnload);
    location.reload();
  }

  function renderAll() {
    A.worksheets.render();
    A.topics.render();
    A.coverage.render();
    A.reports.render();
    A.legal.render();
    A.users.render();
  }

  // Recarrega dados da base sem fechar o editor aberto.
  app.reload = async ({ catalogue = true, worksheets = true, reports = false, legal = false, users = false } = {}) => {
    try {
      await Promise.all([catalogue && A.loadCatalogue(), worksheets && A.loadWorksheets(), (catalogue || worksheets) && A.loadContents(), reports && A.reports.load(),
        legal && A.legal.load(), users && A.users.load()].filter(Boolean));
      renderAll();
    } catch (e) { A.fail(e); }
  };

  let current = 'worksheets';
  app.showTab = (tab) => {
    current = tab;
    document.querySelectorAll('nav.side button').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    document.querySelectorAll('.tab').forEach((el) => { el.hidden = el.id !== 'tab-' + tab; });
    if (tab === 'reports') A.reports.render();
    window.scrollTo({ top: 0 });
    app.sync();
  };

  // ---------- Rotas no endereço (#/…) ----------
  // #/fichas, #/fichas/nova, #/fichas/<id>, #/temas, #/cobertura, #/cobertura/<disciplina>/<ano>,
  // #/relatos, #/documentos, #/planos, #/responsaveis. Funciona também a abrir o ficheiro do disco.
  const SLUG = { worksheets: 'fichas', topics: 'temas', coverage: 'cobertura', reports: 'relatos', legal: 'documentos', plans: 'planos', users: 'responsaveis' };
  const TAB = Object.fromEntries(Object.entries(SLUG).map(([t, s]) => [s, t]));
  let routing = false;

  // Endereço que corresponde ao que está no ecrã.
  function path() {
    const ws = A.editor.currentId();
    if (current === 'worksheets' && ws) { const q = A.editor.query(); return `#/fichas/${ws}${q ? '?' + q : ''}`; }
    if (current === 'coverage') { const o = A.coverage.current(); if (o) return `#/cobertura/${o.subjectId}/${o.year}`; }
    return `#/${SLUG[current] || 'fichas'}`;
  }

  // Atualiza o endereço (cria entrada no histórico, para o «voltar» do navegador funcionar).
  app.sync = () => {
    if ($('appView').hidden) return;
    const want = path();
    if (location.hash === want) return;
    if (routing) history.replaceState(null, '', want); else location.hash = want;
  };

  // Mostra a página do endereço atual.
  async function navigate() {
    if ($('appView').hidden || location.hash === path()) return;
    const [route, query = ''] = location.hash.replace(/^#\/?/, '').split('?');
    const [slug, a, b] = route.split('/');
    const tab = TAB[slug] || 'worksheets';
    const ws = A.editor.currentId();
    if (ws && A.editor.isDirty() && !(tab === 'worksheets' && a === ws)
        && !confirm('Há alterações por gravar nesta ficha. Descartar?')) { app.sync(); return; }
    routing = true;
    try {
      if (tab === 'worksheets' && a) {
        if (a === 'nova') {
          // Ficha nova, pré-preenchida pelos parâmetros (ex.: vinda da Cobertura).
          if (ws !== 'nova' || A.editor.query() !== query) {
            const p = new URLSearchParams(query);
            const prefill = p.get('disciplina') ? { subjectId: p.get('disciplina'), year: Number(p.get('ano')) || 1,
              topicIds: p.getAll('tema'), contentIds: p.getAll('conteudo'), title: p.get('titulo') || '', tier: p.get('tipo') === 'free' ? 'free' : 'premium' } : null;
            await A.editor.open(null, { force: true, prefill, query, returnTo: TAB[p.get('voltar')] || null });
          }
        } else if (a !== ws) await A.editor.open(a, { force: true });
        return;
      }
      if (ws) A.editor.discard();
      if (tab === 'coverage') A.coverage.setOpen(a && Number(b) ? { subjectId: a, year: Number(b) } : null);
      app.showTab(tab);
    } finally { routing = false; app.sync(); }
  }
  window.addEventListener('hashchange', () => { navigate(); });

  function beforeUnload(ev) {
    if (A.editor.isDirty()) { ev.preventDefault(); ev.returnValue = ''; }
  }

  // ---------- Eventos ----------
  $('connect').addEventListener('click', connect);
  $('key').addEventListener('keydown', (e) => { if (e.key === 'Enter') connect(); });
  $('logout').addEventListener('click', logout);
  $('refresh').addEventListener('click', async () => {
    await app.reload({ reports: true, legal: true, users: true });
    A.toast('ok', 'Dados atualizados.', 1800);
  });
  document.querySelectorAll('nav.side button').forEach((b) => b.addEventListener('click', () => app.showTab(b.dataset.tab)));
  window.addEventListener('beforeunload', beforeUnload);

  A.topics.init();
  A.worksheets.init();
  A.editor.init();
  A.reports.init();
  A.coverage.init();
  A.legal.init();
  A.users.init();
})();
