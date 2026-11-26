// Migração de fichas da base ligada (origem) para outra base (destino), ex.: staging → produção.
// 1) Ligar ao destino (URL + chave service_role). 2) Lista das fichas da origem que faltam ou estão diferentes
// no destino, por disciplina › ano › tema; escolher e migrar. As imagens das perguntas são copiadas.
// Ligação entre bases pelo nome: disciplina + ano + título (fichas), temas e conteúdos da grade pelo nome.
// Requer 202611260001_admin_worksheet_digests.sql nas duas bases.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const M = A.migrate = {};
  const key = (s) => A.norm(s).replace(/\s+/g, ' ');
  const wsKey = (d) => [key(d.subject), d.schoolYear, key(d.title)].join('|');

  // Estado da migração (a chave do destino fica só em memória, como a da origem).
  let target = null;        // { url, key, env }
  let tgt = null;           // { subjects, topics, contents, digests }
  let rows = [];            // diferenças (só fichas da origem)
  let busy = false;
  const selected = new Set();

  const envName = (url) => { try { return new URL(url).hostname.split('.')[0]; } catch { return url; } };

  async function pool(items, n, fn) {
    let i = 0;
    await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
      while (i < items.length) { const k = i++; await fn(items[k], k); }
    }));
  }

  // ---------- Ecrã 1: ligar ao destino ----------
  function renderConnect(error = '') {
    $('migBox').innerHTML = `<section class="mig-connect">
      <h3 style="margin-top:0">Base de destino</h3>
      <p class="hint">As fichas saem da base ligada agora (<b>${esc(envName(A.state.url))}</b>) e vão para a base que indicares aqui.
        Usa a chave <code>service_role</code> legacy (JWT) do destino. Fica só em memória.</p>
      <div class="field"><label for="migUrl">URL do projeto de destino</label>
        <input id="migUrl" autocomplete="off" placeholder="https://xxxxxxxx.supabase.co" value="${esc(target?.url || '')}"></div>
      <div class="field"><label for="migKey">Chave <code>service_role</code> do destino</label>
        <input id="migKey" type="password" placeholder="eyJhbGciOi…" autocomplete="off" spellcheck="false"></div>
      <div class="row"><button id="migConnect">Ligar e comparar</button></div>
      <div id="migConnMsg">${error ? A.msg('err', error) : ''}</div>
    </section>`;
    $('migConnect').onclick = connect;
    $('migKey').onkeydown = (e) => { if (e.key === 'Enter') connect(); };
  }

  async function connect() {
    const url = $('migUrl').value.trim().replace(/\/+$/, ''), k = $('migKey').value.trim();
    if (!url || !k) { $('migConnMsg').innerHTML = A.msg('err', 'Indica o URL e a chave do destino.'); return; }
    if (url === A.state.url) { $('migConnMsg').innerHTML = A.msg('err', 'O destino é a mesma base que está ligada. Indica a outra base.'); return; }
    target = { url, key: k, env: envName(url) };
    $('migConnect').disabled = true;
    $('migConnMsg').innerHTML = A.msg('warn', 'A ligar e a comparar as fichas…');
    try {
      await compare();
      renderList();
    } catch (e) {
      target = null;
      renderConnect(esc(e.message) + (e.code === 'MIGRATION_MISSING'
        ? '<br>Aplica <code>202611260001_admin_worksheet_digests.sql</code> nas duas bases.'
        : '<br>Confirma o URL e a chave <b>service_role legacy (JWT)</b> do destino.'));
    }
  }

  // ---------- Comparação ----------
  async function loadTarget() {
    const [cat, contents, digests] = await Promise.all([
      A.rpcOn(target, 'admin_catalogue_overview'),
      A.rpcOn(target, 'admin_list_contents'),
      A.rpcOn(target, 'admin_worksheet_digests'),
    ]);
    tgt = { subjects: cat.subjects || [], topics: cat.topics || [], contents: contents || [], digests: digests || [] };
  }

  const sameList = (a, b) => JSON.stringify(a.map(key).sort()) === JSON.stringify(b.map(key).sort());
  const contentKeys = (cs) => (cs || []).map((c) => `${c.topic}›${c.name}`);

  async function compare() {
    const [src] = await Promise.all([A.rpcOn(A.state, 'admin_worksheet_digests'), loadTarget()]);
    const count = (list) => list.reduce((m, d) => m.set(wsKey(d), (m.get(wsKey(d)) || 0) + 1), new Map());
    const srcCount = count(src), tgtCount = count(tgt.digests);
    const tgtBy = new Map(tgt.digests.map((d) => [wsKey(d), d]));
    rows = [];
    for (const d of src) {
      if (d.status === 'archived') continue; // arquivar não se migra
      const k = wsKey(d), t = tgtBy.get(k);
      const errors = [];
      if (srcCount.get(k) > 1) errors.push('Há mais de uma ficha com este título, disciplina e ano na origem. Muda o título de uma delas.');
      if (tgtCount.get(k) > 1) errors.push('Há mais de uma ficha com este título, disciplina e ano no destino.');
      const subject = tgt.subjects.find((s) => key(s.name) === key(d.subject));
      if (!subject) errors.push(`A disciplina «${d.subject}» não existe no destino (cria-a em Temas).`);
      else for (const name of d.topics) {
        const tp = tgt.topics.find((x) => x.subjectId === subject.id && x.schoolYear === d.schoolYear && key(x.name) === key(name));
        if (tp?.archivedAt) errors.push(`O tema «${name}» está arquivado no destino.`);
      }
      let changes = [];
      if (t) {
        if (t.contentHash !== d.contentHash) changes.push('perguntas');
        if (!sameList(t.topics, d.topics)) changes.push('temas');
        if (t.accessTier !== d.accessTier) changes.push(d.accessTier === 'free' ? 'passa a Free' : 'passa a Premium');
        if (!sameList(contentKeys(t.contents), contentKeys(d.contents))) changes.push('conteúdos da grade');
        if (d.published && !t.published) changes.push('publicação');
        if (!changes.length) continue; // igual no destino
      }
      rows.push({ d, target: t || null, subject, changes, errors });
    }
    // Seleção mantém-se só para as fichas que continuam diferentes e válidas.
    const valid = new Set(rows.filter((r) => !r.errors.length).map((r) => r.d.id));
    [...selected].forEach((id) => { if (!valid.has(id)) selected.delete(id); });
  }

  // ---------- Ecrã 2: lista das diferenças ----------
  const groupTopic = (d) => d.topics.length ? [...d.topics].sort((a, b) => a.localeCompare(b, 'pt'))[0] : 'Sem tema';

  function visibleRows() {
    const q = A.norm($('migSearch')?.value || ''), kind = $('migKind')?.value || '';
    return rows.filter((r) => {
      if (kind === 'new' && r.target) return false;
      if (kind === 'changed' && !r.target) return false;
      if (kind === 'images' && !r.d.imageCount) return false;
      if (q && !q.split(/\s+/).every((p) => A.norm([r.d.title, r.d.subject, ...r.d.topics].join(' ')).includes(p))) return false;
      return true;
    });
  }

  function renderList() {
    const src = envName(A.state.url);
    $('migBox').innerHTML = `<section>
      <div class="row">
        <span class="badge grey">Origem: ${esc(src)}</span> → <span class="badge premium">Destino: ${esc(target.env)}</span>
        <span class="spacer"></span>
        <button class="sm secondary" id="migRecompare">↻ Comparar de novo</button>
        <button class="sm ghost" id="migDisconnect">Trocar destino</button>
      </div>
      <p class="hint mt" style="margin-top:12px">Fichas da origem que <b>não existem</b> no destino ou que estão <b>diferentes</b> (perguntas, temas, Free/Premium,
        conteúdos da grade ou publicação). O que só existe no destino não aparece. Fichas arquivadas não se migram.
        Ao migrar: as imagens das perguntas são copiadas, temas e conteúdos em falta são criados, e a ficha fica
        <b>publicada se está publicada na origem</b> (no destino, uma ficha que já existe ganha uma versão nova).</p>
      <div class="filters" style="grid-template-columns: 2fr 1fr">
        <input id="migSearch" class="search" type="search" placeholder="Procurar por título, disciplina ou tema…">
        <select id="migKind"><option value="">Novas e alteradas</option><option value="new">Só novas</option>
          <option value="changed">Só alteradas</option><option value="images">Só com imagens</option></select>
      </div>
      <div id="migList"></div>
    </section>
    <div class="savebar"><div class="inner">
      <span class="status" id="migStatus"></span>
      <button class="secondary" id="migAll">Selecionar visíveis</button>
      <button class="secondary" id="migNone">Limpar seleção</button>
      <button id="migRun">Migrar selecionadas</button>
    </div></div>`;
    $('migRecompare').onclick = recompare;
    $('migDisconnect').onclick = () => { if (busy) return; target = null; tgt = null; rows = []; selected.clear(); renderConnect(); };
    $('migSearch').oninput = renderGroups;
    $('migKind').oninput = renderGroups;
    $('migAll').onclick = () => { visibleRows().filter((r) => !r.errors.length).forEach((r) => selected.add(r.d.id)); renderGroups(); };
    $('migNone').onclick = () => { selected.clear(); renderGroups(); };
    $('migRun').onclick = run;
    $('migList').onchange = (ev) => {
      const el = ev.target;
      if (el.dataset.id) { el.checked ? selected.add(el.dataset.id) : selected.delete(el.dataset.id); }
      else if (el.dataset.group) {
        rows.filter((r) => groupId(r) === el.dataset.group && !r.errors.length && visibleRows().includes(r))
          .forEach((r) => (el.checked ? selected.add(r.d.id) : selected.delete(r.d.id)));
      }
      renderGroups();
    };
    renderGroups();
  }

  const groupId = (r) => `${r.d.subject}|${r.d.schoolYear}|${groupTopic(r.d)}`;

  function renderGroups() {
    const list = visibleRows();
    const status = $('migStatus');
    const selRows = rows.filter((r) => selected.has(r.d.id));
    const imgs = selRows.reduce((n, r) => n + r.d.imageCount, 0);
    status.innerHTML = `<b>${selRows.length}</b> selecionada(s) de ${rows.filter((r) => !r.errors.length).length}` +
      (imgs ? ` • ${imgs} imagem(ns)` : '') + (list.length !== rows.length ? ` • a mostrar ${list.length}` : '');
    $('migRun').disabled = busy || !selRows.length;
    if (!rows.length) { $('migList').innerHTML = `<div class="empty">Nada a migrar: as fichas da origem estão iguais no destino.</div>`; return; }
    if (!list.length) { $('migList').innerHTML = '<div class="empty">Nenhuma ficha corresponde aos filtros.</div>'; return; }

    // Disciplina › (ano › tema)
    const bySubject = new Map();
    for (const r of list) {
      if (!bySubject.has(r.d.subject)) bySubject.set(r.d.subject, new Map());
      const g = bySubject.get(r.d.subject), gid = groupId(r);
      if (!g.has(gid)) g.set(gid, []);
      g.get(gid).push(r);
    }
    const subjects = [...bySubject.keys()].sort((a, b) => a.localeCompare(b, 'pt'));
    $('migList').innerHTML = subjects.map((s) => {
      const groups = [...bySubject.get(s).entries()].sort(([, a], [, b]) =>
        a[0].d.schoolYear - b[0].d.schoolYear || groupTopic(a[0].d).localeCompare(groupTopic(b[0].d), 'pt'));
      const n = groups.reduce((x, [, g]) => x + g.length, 0);
      return `<div class="mig-subject"><h3>${esc(s)} <span class="badge grey">${n}</span></h3>` + groups.map(([gid, g]) => {
        const ok = g.filter((r) => !r.errors.length), on = ok.filter((r) => selected.has(r.d.id)).length;
        const box = `<input type="checkbox" data-group="${esc(gid)}" ${ok.length && on === ok.length ? 'checked' : ''} ${ok.length ? '' : 'disabled'}>`;
        return `<div class="mig-group">
          <label class="mig-ghead">${box}<span>${g[0].d.schoolYear}.º ano › ${esc(groupTopic(g[0].d))}</span>
            <span class="muted small">${on ? `${on} de ` : ''}${g.length}</span></label>
          ${g.sort((a, b) => a.d.title.localeCompare(b.d.title, 'pt')).map(item).join('')}
        </div>`;
      }).join('') + '</div>';
    }).join('');
    // Estado «indeterminado» dos grupos com seleção parcial.
    $('migList').querySelectorAll('input[data-group]').forEach((el) => {
      const g = rows.filter((r) => groupId(r) === el.dataset.group && !r.errors.length && list.includes(r));
      const on = g.filter((r) => selected.has(r.d.id)).length;
      el.indeterminate = on > 0 && on < g.length;
    });
  }

  function item(r) {
    const d = r.d;
    const badges = [
      r.target ? `<span class="badge warn" title="Já existe no destino">Alterada: ${esc(r.changes.join(', '))}</span>` : '<span class="badge ok">Nova</span>',
      d.accessTier === 'free' ? '<span class="badge ok">Free</span>' : '<span class="badge premium">★ Premium</span>',
      d.published ? '' : '<span class="badge warn">Rascunho na origem</span>',
      `<span class="badge grey">${d.questionCount} perguntas</span>`,
      d.imageCount ? `<span class="badge grey">🖼 ${d.imageCount}</span>` : '',
      d.topics.length > 1 ? `<span class="badge grey" title="${esc(d.topics.join(', '))}">+${d.topics.length - 1} tema(s)</span>` : '',
    ].join(' ');
    return `<label class="mig-item ${r.errors.length ? 'blocked' : ''}">
      <input type="checkbox" data-id="${d.id}" ${selected.has(d.id) ? 'checked' : ''} ${r.errors.length || busy ? 'disabled' : ''}>
      <span><span class="t">${esc(d.title)}</span><span class="badges">${badges}</span>
        ${r.errors.length ? `<span class="q-err">${r.errors.map(esc).join('<br>')}</span>` : ''}</span>
    </label>`;
  }

  async function recompare() {
    if (busy) return;
    $('migRecompare').disabled = true;
    try { await compare(); renderGroups(); A.toast('ok', 'Comparação atualizada.', 1800); }
    catch (e) { A.fail(e); }
    finally { if ($('migRecompare')) $('migRecompare').disabled = false; }
  }

  // ---------- Migrar ----------
  // Copia uma imagem da origem para o destino com o mesmo caminho. Já existir no destino não é erro.
  async function copyImage(path) {
    const enc = String(path).split('/').map(encodeURIComponent).join('/');
    const head = await fetch(A.imageUrl(path, target.url), { method: 'HEAD' }).catch(() => null);
    if (head && head.ok) return 'exists';
    const res = await fetch(A.imageUrl(path)).catch((e) => { throw new Error(`imagem ${path}: ${e.message}`); });
    if (!res.ok) throw new Error(`imagem ${path} não encontrada na origem (HTTP ${res.status})`);
    const blob = await res.blob();
    const up = await fetch(`${target.url}/storage/v1/object/${A.IMAGE_BUCKET}/${enc}`, {
      method: 'POST', body: blob,
      headers: { ...A.authHeaders(target), 'Content-Type': blob.type || 'application/octet-stream', 'Cache-Control': '31536000', 'x-upsert': 'false' },
    });
    if (up.ok) return 'copied';
    const body = await up.json().catch(() => null);
    if (up.status === 409 || /already exists|duplicate/i.test(body?.message || body?.error || '')) return 'exists';
    if (/bucket not found/i.test(body?.message || '')) throw new Error('O bucket question-images não existe no destino. Aplica 202611220001_question_images_bucket.sql.');
    throw new Error(`imagem ${path}: ${body?.message || body?.error || 'HTTP ' + up.status}`);
  }

  async function migrateOne(r, log) {
    const d = r.d, sid = r.subject.id, yr = d.schoolYear;
    const full = await A.rpcOn(A.state, 'admin_get_worksheet', { p_id: d.id });
    const content = full.latest.content;
    // 1) Imagens
    const paths = [...new Set((content.questions || []).map((q) => q.image?.path).filter(Boolean))];
    for (const p of paths) log[(await copyImage(p)) === 'copied' ? 'imgCopied' : 'imgExisting']++;
    // 2) Temas
    const topicIds = [];
    for (const name of d.topics) {
      const t = tgt.topics.find((x) => x.subjectId === sid && x.schoolYear === yr && key(x.name) === key(name));
      if (!t) throw new Error(`tema «${name}» não encontrado no destino`);
      topicIds.push(t.id);
    }
    // 3) Ficha: grava como rascunho, acerta Free/Premium (o limite de perguntas Free é validado ao publicar) e publica.
    const args = { p_worksheet_id: r.target?.id || null, p_subject_id: sid, p_school_year: yr, p_topic_ids: topicIds,
      p_title: d.title, p_content: content, p_publish: false };
    const saved = await A.rpcOn(target, 'admin_save_worksheet', args);
    if ((r.target?.accessTier || 'premium') !== d.accessTier) {
      await A.rpcOn(target, 'admin_set_worksheet_tier', { p_id: saved.worksheetId, p_tier: d.accessTier });
    }
    if (d.published) await A.rpcOn(target, 'admin_save_worksheet', { ...args, p_worksheet_id: saved.worksheetId, p_publish: true });
    // 4) Conteúdos da grade (criados antes, em lote)
    if (d.contents.length || r.target?.contents?.length) {
      const ids = d.contents.map((c) => tgt.contents.find((x) => x.subjectId === sid && x.schoolYear === yr
        && key(tgt.topics.find((t) => t.id === x.topicId)?.name) === key(c.topic) && key(x.name) === key(c.name))?.id);
      if (ids.some((id) => !id)) throw new Error('conteúdo da grade não encontrado no destino');
      await A.rpcOn(target, 'admin_set_worksheet_contents', { p_worksheet_id: saved.worksheetId, p_content_ids: [...new Set(ids)] });
    }
    log[r.target ? 'updated' : 'created']++;
  }

  async function run() {
    const todo = rows.filter((r) => selected.has(r.d.id) && !r.errors.length);
    if (!todo.length || busy) return;
    const fresh = todo.filter((r) => !r.target).length, imgs = todo.reduce((n, r) => n + r.d.imageCount, 0);
    const ok = await A.dialog({
      title: `Migrar ${todo.length} ficha(s) para «${target.env}»?`, ok: 'Migrar',
      body: `<p>De <b>${esc(envName(A.state.url))}</b> para <b>${esc(target.env)}</b>:</p>
        <ul class="small"><li>${fresh} nova(s), ${todo.length - fresh} alterada(s) (versão nova no destino)</li>
        <li>${imgs} imagem(ns) de perguntas</li>
        <li>Publicadas na origem ficam publicadas no destino e passam logo a ser vistas pelos responsáveis.</li></ul>`,
    });
    if (!ok) return;
    busy = true;
    renderGroups();
    const log = { created: 0, updated: 0, topics: 0, imgCopied: 0, imgExisting: 0, failed: [] };
    try {
      // Conteúdos da grade em falta (cria também os temas desses conteúdos).
      const items = [], seen = new Set();
      for (const r of todo) for (const c of r.d.contents) {
        const k = [r.subject.id, r.d.schoolYear, key(c.topic), key(c.name)].join('|');
        if (seen.has(k)) continue;
        seen.add(k);
        items.push({ subjectId: r.subject.id, schoolYear: r.d.schoolYear, topicName: c.topic, name: c.name, semester: c.semester ?? null });
      }
      for (let i = 0; i < items.length; i += 1000) await A.rpcOn(target, 'admin_import_contents', { p_items: items.slice(i, i + 1000) });
      if (items.length) await loadTarget();
      // Temas em falta, um de cada vez (em paralelo, duas fichas podiam tentar criar o mesmo tema).
      for (const r of todo) for (const name of r.d.topics) {
        const sid = r.subject.id, yr = r.d.schoolYear;
        if (tgt.topics.some((x) => x.subjectId === sid && x.schoolYear === yr && key(x.name) === key(name))) continue;
        const t = await A.rpcOn(target, 'admin_save_topic', { p_id: null, p_subject_id: sid, p_school_year: yr, p_name: name });
        tgt.topics.push({ ...t, subjectId: sid, schoolYear: yr, name, archivedAt: null });
        log.topics++;
      }

      let done = 0;
      await pool(todo, 4, async (r) => {
        try { await migrateOne(r, log); selected.delete(r.d.id); }
        catch (e) { log.failed.push(`${r.d.subject} ${r.d.schoolYear}.º • ${r.d.title}: ${e.message}`); }
        done++;
        $('migStatus').innerHTML = `A migrar… <b>${done}</b> de ${todo.length}`;
      });
    } catch (e) {
      log.failed.push(e.message);
    } finally {
      busy = false;
    }
    try { await compare(); } catch (e) { log.failed.push('Comparação final: ' + e.message); }
    renderGroups();
    const text = `${log.created} criada(s), ${log.updated} atualizada(s) em «${target.env}»` +
      `${log.topics ? `, ${log.topics} tema(s) criado(s)` : ''}. Imagens: ${log.imgCopied} copiada(s)` +
      `${log.imgExisting ? `, ${log.imgExisting} já existiam` : ''}.`;
    if (log.failed.length) {
      await A.dialog({ title: 'Migração concluída com erros', info: true, ok: 'Fechar',
        body: A.msg('warn', esc(text)) + A.msg('err', `<ul class="small">${log.failed.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>`) });
    } else A.toast('ok', text, 7000);
  }

  M.render = () => {
    if (!$('migBox')) return;
    if (!target) { if (!$('migUrl')) renderConnect(); }
    else if (!$('migList')) renderList();
  };
  M.isBusy = () => busy;
})();
