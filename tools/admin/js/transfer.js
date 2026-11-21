// Exportar / importar fichas entre ambientes (ex.: staging → produção) num ficheiro JSON.
// A ficha é identificada pelo par disciplina + título + ano (os ids mudam entre ambientes);
// disciplinas, temas e conteúdos são ligados pelo nome.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const T = A.transfer = {};
  const FORMAT = 'escola-em-dia/worksheets';
  const key = (s) => A.norm(s).replace(/\s+/g, ' ');

  // Corre fn em paralelo (n de cada vez), mantendo a ordem dos resultados.
  async function pool(items, n, fn) {
    const out = new Array(items.length);
    let i = 0;
    await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
      while (i < items.length) { const k = i++; out[k] = await fn(items[k], k); }
    }));
    return out;
  }

  // ---------- Exportar ----------
  T.export = async () => {
    const list = A.worksheets.filtered();
    if (!list.length) { A.toast('warn', 'Nenhuma ficha nos filtros atuais.'); return; }
    if (!confirm(`Exportar ${list.length} ficha(s) (as dos filtros atuais)?\n\nExporta a versão mais recente de cada uma (rascunho incluído), com temas, conteúdos da grade e Free/Premium.`)) return;
    try {
      A.toast('info', `A exportar ${list.length} ficha(s)…`, 2500);
      const items = await pool(list, 5, async (w) => {
        const d = await A.rpc('admin_get_worksheet', { p_id: w.id });
        const l = d.latest;
        return {
          title: d.title, subject: w.subjectName, schoolYear: l.schoolYear, accessTier: d.accessTier, status: d.status,
          published: !!l.publishedAt,
          topics: l.topicIds.map((id) => A.topic(id)?.name).filter(Boolean),
          contents: A.state.contents.filter((c) => c.worksheetIds.includes(w.id))
            .map((c) => ({ topic: A.topic(c.topicId)?.name, name: c.name, semester: c.semester })),
          content: l.content,
        };
      });
      const env = new URL(A.state.url).hostname.split('.')[0];
      const data = { format: FORMAT, version: 1, exportedAt: new Date().toISOString(), source: env, worksheets: items };
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = `fichas-${env}-${new Date().toISOString().slice(0, 10)}-${items.length}.json`;
      document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
      A.toast('ok', `${items.length} ficha(s) exportadas.`);
    } catch (e) { A.fail(e); }
  };

  // ---------- Importar ----------
  function parse(text) {
    let data;
    try { data = JSON.parse(text); } catch (e) { throw new Error('Ficheiro inválido: ' + e.message); }
    if (!data || data.format !== FORMAT || !Array.isArray(data.worksheets)) throw new Error('Este ficheiro não é uma exportação de fichas do admin.');
    return data;
  }

  // Analisa cada ficha do ficheiro contra o ambiente atual.
  function plan(data) {
    return data.worksheets.map((it, i) => {
      const subject = A.state.subjects.find((s) => key(s.name) === key(it.subject));
      const r = { i, it, subject, errors: [], newTopics: [] };
      if (!subject) { r.errors.push(`Disciplina «${it.subject}» não existe neste ambiente (cria-a em Temas).`); return r; }
      if (!it.title || !it.content || !Array.isArray(it.content.questions)) r.errors.push('Ficha sem título ou sem perguntas.');
      if (!(it.schoolYear >= 1 && it.schoolYear <= 9)) r.errors.push('Ano escolar inválido.');
      if (!it.topics?.length) r.errors.push('Ficha sem temas.');
      for (const name of it.topics || []) {
        const t = A.state.topics.find((x) => x.subjectId === subject.id && x.schoolYear === it.schoolYear && key(x.name) === key(name));
        if (!t) r.newTopics.push(name);
        else if (t.archivedAt) r.errors.push(`O tema «${name}» está arquivado neste ambiente.`);
      }
      r.existing = A.state.worksheets.find((w) => w.subjectId === subject.id && key(w.title) === key(it.title) && w.latest?.schoolYear === it.schoolYear);
      return r;
    });
  }

  T.import = () => {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = '.json,application/json';
    input.onchange = async () => {
      const file = input.files[0];
      if (!file) return;
      let data;
      try { data = parse(await file.text()); } catch (e) { A.fail(e); return; }
      await review(data);
    };
    input.click();
  };

  async function review(data) {
    const rows = plan(data);
    const ok = rows.filter((r) => !r.errors.length), bad = rows.filter((r) => r.errors.length);
    const fresh = ok.filter((r) => !r.existing), dup = ok.filter((r) => r.existing);
    const topicsNew = [...new Set(ok.flatMap((r) => r.newTopics.map((t) => `${r.subject.name} ${r.it.schoolYear}.º › ${t}`)))];
    const line = (r) => `<li>${esc(r.it.title)} <span class="muted small">• ${esc(r.it.subject)} ${r.it.schoolYear}.º • ${r.it.accessTier === 'free' ? 'Free' : 'Premium'}${r.it.published ? '' : ' • rascunho na origem'}</span>${r.errors.length ? `<div class="small" style="color:var(--error)">${r.errors.map(esc).join('<br>')}</div>` : ''}</li>`;
    const env = new URL(A.state.url).hostname.split('.')[0];
    const res = await A.dialog({
      title: `Importar ${rows.length} ficha(s) para «${env}»`,
      ok: 'Importar',
      body: `<p class="hint">Origem: <b>${esc(data.source || '?')}</b>, exportado em ${A.fmtDate(data.exportedAt)}. Destino: <b>${esc(env)}</b>.</p>
        <div class="field"><label>Fichas novas: ${fresh.length}</label>${fresh.length ? `<details><summary class="small">Ver</summary><ul class="small">${fresh.map(line).join('')}</ul></details>` : ''}</div>
        ${dup.length ? `<div class="field"><label>Já existem (mesma disciplina, título e ano): ${dup.length}</label>
          <select name="dup"><option value="skip">Ignorar as que já existem</option><option value="update">Atualizar (cria versão nova se o conteúdo mudou)</option></select>
          <details><summary class="small">Ver</summary><ul class="small">${dup.map(line).join('')}</ul></details></div>` : ''}
        ${bad.length ? A.msg('err', `<b>${bad.length} com erros (não são importadas):</b><ul class="small">${bad.map(line).join('')}</ul>`) : ''}
        ${topicsNew.length ? A.msg('info', `Temas a criar: ${topicsNew.map(esc).join(', ')}.`) : ''}
        <div class="field"><label>Como gravar</label>
          <select name="mode"><option value="draft">Como rascunho (revês e publicas depois)</option>
            <option value="source">Publicar as que estão publicadas na origem</option></select></div>
        <div class="field"><label><input type="checkbox" name="tier" checked style="width:auto"> Manter Free/Premium da origem</label></div>`,
      onSubmit: (form) => ({ dup: form.dup?.value || 'skip', mode: form.mode.value, tier: form.tier.checked }),
    });
    if (!res || res === true) return;
    const todo = ok.filter((r) => !r.existing || res.dup === 'update');
    if (!todo.length) { A.toast('warn', 'Nada para importar.'); return; }
    await run(todo, res, env);
  }

  async function run(todo, opts, env) {
    const log = { created: 0, updated: 0, failed: [] };
    A.toast('info', `A importar ${todo.length} ficha(s)…`, 3000);
    try {
      // 1) Conteúdos da grade (criam também os temas que faltarem).
      if (!A.state.contentsMissing) {
        const items = todo.flatMap((r) => (r.it.contents || []).filter((c) => c.topic && c.name).map((c) => ({
          subjectId: r.subject.id, schoolYear: r.it.schoolYear, topicName: c.topic, name: c.name, semester: c.semester || null })));
        const seen = new Set();
        const uniq = items.filter((x) => { const k = [x.subjectId, x.schoolYear, key(x.topicName), key(x.name)].join('|'); return !seen.has(k) && seen.add(k); });
        for (let i = 0; i < uniq.length; i += 1000) await A.rpc('admin_import_contents', { p_items: uniq.slice(i, i + 1000) });
      }
      await Promise.all([A.loadCatalogue(), A.loadContents()]);
    } catch (e) { A.fail(e); return; }

    for (const r of todo) {
      const it = r.it;
      try {
        // 2) Temas em falta.
        const topicIds = [];
        for (const name of it.topics) {
          let t = A.state.topics.find((x) => x.subjectId === r.subject.id && x.schoolYear === it.schoolYear && key(x.name) === key(name));
          if (!t) {
            t = await A.rpc('admin_save_topic', { p_id: null, p_subject_id: r.subject.id, p_school_year: it.schoolYear, p_name: name });
            A.state.topics.push({ ...t, archivedAt: null });
          }
          topicIds.push(t.id);
        }
        // 3) Ficha. Free com publicação: muda o tipo antes, para o limite de perguntas ser validado como na origem.
        const publish = opts.mode === 'source' && it.published;
        const saved = await A.rpc('admin_save_worksheet', {
          p_worksheet_id: r.existing ? r.existing.id : null, p_subject_id: r.subject.id, p_school_year: it.schoolYear,
          p_topic_ids: topicIds, p_title: it.title, p_content: it.content, p_publish: false,
        });
        if (opts.tier && it.accessTier && (r.existing ? r.existing.accessTier : 'premium') !== it.accessTier) {
          await A.rpc('admin_set_worksheet_tier', { p_id: saved.worksheetId, p_tier: it.accessTier });
        }
        if (publish) {
          await A.rpc('admin_save_worksheet', {
            p_worksheet_id: saved.worksheetId, p_subject_id: r.subject.id, p_school_year: it.schoolYear,
            p_topic_ids: topicIds, p_title: it.title, p_content: it.content, p_publish: true,
          });
        }
        // 4) Conteúdos da ficha.
        if (!A.state.contentsMissing && it.contents?.length) {
          const ids = it.contents.map((c) => A.state.contents.find((x) => x.subjectId === r.subject.id && x.schoolYear === it.schoolYear
            && key(A.topic(x.topicId)?.name) === key(c.topic) && key(x.name) === key(c.name))?.id).filter(Boolean);
          if (ids.length) await A.rpc('admin_set_worksheet_contents', { p_worksheet_id: saved.worksheetId, p_content_ids: [...new Set(ids)] });
        }
        log[r.existing ? 'updated' : 'created']++;
      } catch (e) {
        log.failed.push(`${it.title}: ${e.message}`);
      }
    }
    await A.app.reload();
    const text = `${log.created} criada(s), ${log.updated} atualizada(s) em «${env}»${opts.mode === 'draft' ? ' (como rascunho)' : ''}.`;
    if (log.failed.length) {
      await A.dialog({ title: 'Importação concluída com erros', info: true, ok: 'Fechar',
        body: A.msg('warn', esc(text)) + A.msg('err', `<ul class="small">${log.failed.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>`) });
    } else A.toast('ok', text, 6000);
  }
})();
