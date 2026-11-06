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
      await Promise.all([A.loadCatalogue(), A.loadWorksheets(), A.reports.load()]);
      $('key').value = '';
      box.innerHTML = '';
      $('loginView').hidden = true;
      $('appView').hidden = false;
      $('connLabel').textContent = new URL(url).hostname.split('.')[0];
      renderAll();
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
    A.reports.render();
  }

  // Recarrega dados da base sem fechar o editor aberto.
  app.reload = async ({ catalogue = true, worksheets = true, reports = false } = {}) => {
    try {
      await Promise.all([catalogue && A.loadCatalogue(), worksheets && A.loadWorksheets(), reports && A.reports.load()].filter(Boolean));
      renderAll();
    } catch (e) { A.fail(e); }
  };

  app.showTab = (tab) => {
    document.querySelectorAll('nav.tabs button').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    document.querySelectorAll('.tab').forEach((el) => { el.hidden = el.id !== 'tab-' + tab; });
    if (tab === 'reports') A.reports.render();
    window.scrollTo({ top: 0 });
  };

  function beforeUnload(ev) {
    if (A.editor.isDirty()) { ev.preventDefault(); ev.returnValue = ''; }
  }

  // ---------- Eventos ----------
  $('connect').addEventListener('click', connect);
  $('key').addEventListener('keydown', (e) => { if (e.key === 'Enter') connect(); });
  $('logout').addEventListener('click', logout);
  $('refresh').addEventListener('click', async () => {
    await app.reload({ reports: true });
    A.toast('ok', 'Dados atualizados.', 1800);
  });
  document.querySelectorAll('nav.tabs button').forEach((b) => b.addEventListener('click', () => app.showTab(b.dataset.tab)));
  window.addEventListener('beforeunload', beforeUnload);

  A.topics.init();
  A.worksheets.init();
  A.editor.init();
  A.reports.init();
})();
