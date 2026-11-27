// Gerar fichas com o Gemini para um conteúdo da grade (Cobertura › disciplina × ano › conteúdo › ✨).
// Por omissão: 1 Free de 6 perguntas + 3 Premium de 8, 10 e 12, publicadas. Um pedido ao Gemini por ficha,
// em sequência (cada pedido recebe as perguntas já feitas para não as repetir).
// Perguntas que pedem imagem: ficam com a imagem provisória + descrição pronta e a ficha fica em rascunho.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const AI = A.aiGen = {};
  const DEFAULT_PLAN = [{ tier: 'free', count: 6 }, { tier: 'premium', count: 8 }, { tier: 'premium', count: 10 }, { tier: 'premium', count: 12 }];
  const LANG = /portugu|ingl|ingles|english|franc|espanhol|alem/;
  const jobs = []; // gerações desta sessão (para o painel na Cobertura)

  // ---------- Prompt ----------
  function cycleRules({ year, subject, tier, count, written }) {
    const lang = LANG.test(A.norm(subject));
    if (year <= 4) {
      return [
        `1.º Ciclo (${year}.º ano): as crianças estão a aprender a ler e a escrever. Enunciados muito curtos e claros.`,
        'Sobretudo escolha múltipla e verdadeiro/falso; no máximo 1 resposta aberta ("written"), de uma só palavra.',
        lang ? 'Se o conteúdo for de leitura/compreensão, inclui em "text" um texto de leitura curto e original (até 80 palavras).' : '',
        year === 1 ? 'Usa emojis nos enunciados e nas opções para ajudar a criança a perceber as palavras (ex.: «🐱 gato»), exceto no que uma imagem pedida já mostra.' : 'Podes usar alguns emojis para tornar a ficha mais amigável.',
      ];
    }
    return [
      `${year <= 6 ? '2.º' : '3.º'} Ciclo (${year}.º ano): as crianças já leem e escrevem com autonomia. Sem emojis.`,
      `Exatamente ${written} pergunta(s) de resposta aberta ("written"); as restantes de escolha múltipla e verdadeiro/falso.`,
      lang ? (tier === 'free'
        ? 'Inclui em "text" um texto original de 200 a 250 palavras; as perguntas incidem sobre o texto e o conteúdo.'
        : `Inclui em "text" um texto original de 300 a 450 palavras; as perguntas incidem sobre o texto e o conteúdo.${count >= 10 ? ' A última pergunta é uma produção escrita de 60 a 120 palavras ("written").' : ''}`)
        : 'Quando ajudar, contextualiza com situações do dia a dia (problemas, dados, exemplos concretos).',
      lang ? 'Se o texto for um conto ou narrativa original, termina-o com a nota «(Conto de autor escrito para a Escola em Dia)».' : '',
    ];
  }

  AI.buildPrompt = ({ subject, year, topic, content, semester, tier, count, title, avoid, extra, maxImages }) => {
    const written = year <= 4 ? (count >= 8 ? 1 : 0) : Math.ceil(count / 3);
    const rules = cycleRules({ year, subject, tier, count, written }).filter(Boolean);
    return `És um professor do ensino básico em Portugal. Cria UMA ficha de exercícios para uma criança do ${year}.º ano,
disciplina de ${subject}, tema «${topic}», conteúdo da grade «${content}»${semester ? ` (${semester}.º semestre)` : ''}, alinhada com as Aprendizagens Essenciais.
Título da ficha (não alterar): «${title}». Tipo: ${tier === 'free' ? 'Free (gratuita)' : 'Premium'}.

Composição: exatamente ${count} perguntas, todas sobre o conteúdo «${content}».
${rules.map((r) => '• ' + r).join('\n')}

Regras de conteúdo:
• Português de Portugal (pt-PT)${A.norm(subject).includes('ingl') ? ', exceto o que for para trabalhar em inglês (textos, frases e opções em inglês; instruções podem ser em português)' : ''}; frases claras e adequadas à idade (${year + 5}–${year + 6} anos).
• Escolha múltipla com 3 ou 4 opções e uma só certa; varia a posição da resposta certa; opções erradas plausíveis.
• Equilibra as respostas verdadeiro/falso (não ponhas todas iguais).
• Sem dados pessoais, marcas, violência ou temas sensíveis.
• "explanation": curta e encorajadora para a criança (escolha múltipla e verdadeiro/falso); nas abertas, a resposta esperada e os critérios para os responsáveis.
• Começa com uma "instructions" curta e amigável para a criança.
${avoid.length ? `• NÃO repitas nem reformules estas perguntas, que já existem noutras fichas deste conteúdo:\n${avoid.map((p) => `  - ${p}`).join('\n')}\n` : ''}${extra ? `\nIndicações adicionais: ${extra}\n` : ''}
Imagens:
• Só pede imagem numa pergunta quando ela ajuda MESMO a perceber ou a responder (observar uma cena, uma figura, uma capa, um gráfico simples). Se não for preciso, não peças. No máximo ${maxImages} imagem(ns) nesta ficha.
• Numa pergunta com imagem, acrescenta "imageRequest": { "description": "descrição completa da cena para gerar ou procurar a imagem", "alt": "texto alternativo curto para leitores de ecrã (até 200 caracteres)" }.
• A descrição diz tudo o que a imagem tem de mostrar (e o que NÃO pode mostrar, se a resposta depender disso). Sem texto nem letras na imagem; números só se forem essenciais (diz quais).
• O enunciado dessa pergunta refere a imagem (ex.: «Observa a imagem.») e não a descreve com emojis.

Formato: responde APENAS com um objeto JSON válido, sem texto antes ou depois, com esta estrutura
(sem "title"; "imageRequest" só nas perguntas que precisam de imagem):

${A.schemaDoc.replace(/"title": "[^"]*",\n\s*/, '').replace(/("correctAnswer": "b",)/, '$1\n      "imageRequest": { "description": "…", "alt": "…" },')}`;
  };

  // ---------- Diálogo de configuração ----------
  const planRow = (p, i) => `<div class="ai-plan-row" data-i="${i}">
      <span class="num">${i + 1}</span>
      <select data-p="tier"><option value="free" ${p.tier === 'free' ? 'selected' : ''}>Free</option><option value="premium" ${p.tier === 'premium' ? 'selected' : ''}>Premium</option></select>
      <input data-p="count" type="number" min="1" max="50" value="${p.count}"><span class="small muted">perguntas</span>
      <button type="button" class="icon" data-p="del" title="Retirar">✕</button>
    </div>`;

  AI.open = async (contentId) => {
    if (!A.gemini.ready()) {
      if (confirm('Ainda não configuraste o token do Gemini. Abrir Configurações › Gemini?')) A.app.showTab('gemini');
      return;
    }
    const c = A.state.contents.find((x) => x.id === contentId);
    if (!c) return;
    const subject = A.subject(c.subjectId)?.name || '', topic = A.topic(c.topicId)?.name || '';
    const linked = c.worksheetIds.length;
    const pub = A.state.worksheets.filter((w) => c.worksheetIds.includes(w.id) && w.status === 'published');
    const nFree = pub.filter((w) => w.accessTier === 'free').length, nPrem = pub.length - nFree;
    const done = nFree >= A.coverage.MIN_FREE && nPrem >= A.coverage.MIN_PREMIUM;
    let plan = DEFAULT_PLAN.map((p) => ({ ...p }));
    const promise = A.dialog({
      title: '✨ Gerar fichas com IA', ok: 'Gerar',
      body: `<p class="hint" style="margin-bottom:10px"><b>${esc(subject)} • ${c.schoolYear}.º ano</b> › ${esc(topic)} › <b>${esc(c.name)}</b><br>
          ${linked ? `Já há ${linked} ficha(s) ligada(s) a este conteúdo: as perguntas delas são enviadas ao Gemini para não as repetir.` : 'Ainda não há fichas ligadas a este conteúdo.'}</p>
        ${done ? A.msg('warn', `Este conteúdo já tem a meta: ${nFree} Free e ${nPrem} Premium publicadas.`) : pub.length ? A.msg('info', `Publicadas: ${nFree} Free e ${nPrem} Premium (meta: ${A.coverage.MIN_FREE} Free e ${A.coverage.MIN_PREMIUM} Premium).`) : ''}
        <div class="field"><label>Fichas a gerar</label><div id="aiPlan"></div>
          <button type="button" class="sm secondary" id="aiAdd">+ Ficha</button></div>
        <div class="field"><label for="aiState">Depois de gerar</label>
          <select id="aiState" name="state"><option value="publish">Publicar</option><option value="draft">Guardar como rascunho</option></select>
          <div class="hint" style="margin:6px 0 0">Fichas com imagens a criar ficam sempre em rascunho (com imagem provisória e a descrição pronta).</div></div>
        <div class="field"><label for="aiImages">Imagens por ficha (máximo)</label>
          <input id="aiImages" name="images" type="number" min="0" max="10" value="${c.schoolYear <= 4 ? 3 : 2}"></div>
        <div class="field"><label for="aiExtra">Indicações extra para o Gemini (opcional)</label>
          <textarea id="aiExtra" name="extra" placeholder="Ex.: usar situações de compras no supermercado; incluir uma pergunta sobre…"></textarea></div>
        <p class="hint" style="margin:0">Modelo <b>${esc(A.gemini.config().model)}</b> • um pedido por ficha.</p>`,
      onSubmit: (form) => {
        if (!plan.length) throw new Error('Indica pelo menos uma ficha.');
        if (plan.some((p) => !(p.count >= 1 && p.count <= 50))) throw new Error('Cada ficha tem de ter entre 1 e 50 perguntas.');
        return { plan: plan.map((p) => ({ ...p })), publish: form.state.value === 'publish',
          maxImages: Math.max(0, Math.min(10, Number(form.images.value) || 0)), extra: form.extra.value.trim() };
      },
    });
    const box = $('aiPlan');
    const draw = () => { box.innerHTML = plan.map(planRow).join(''); };
    draw();
    box.oninput = (ev) => {
      const row = ev.target.closest('.ai-plan-row'); if (!row) return;
      const p = plan[Number(row.dataset.i)];
      if (ev.target.dataset.p === 'tier') p.tier = ev.target.value;
      if (ev.target.dataset.p === 'count') p.count = Number(ev.target.value);
    };
    box.onclick = (ev) => {
      if (ev.target.dataset.p !== 'del') return;
      plan.splice(Number(ev.target.closest('.ai-plan-row').dataset.i), 1); draw();
    };
    $('aiAdd').onclick = () => { plan.push({ tier: 'premium', count: 10 }); draw(); };
    const opts = await promise;
    if (!opts || opts === true) return;
    run(c, opts);
  };

  // ---------- Geração ----------
  async function freeMaxQuestions(c) {
    const anyId = c.worksheetIds[0] || A.state.worksheets[0]?.id;
    if (!anyId) return 6;
    try { return (await A.rpc('admin_get_worksheet', { p_id: anyId })).freeMaxQuestions || 6; } catch { return 6; }
  }

  // Perguntas das fichas já ligadas ao conteúdo (para o Gemini não as repetir).
  async function existingPrompts(c) {
    const out = [];
    for (const id of c.worksheetIds.slice(0, 10)) {
      try {
        const d = await A.rpc('admin_get_worksheet', { p_id: id });
        (d.latest?.content?.questions || []).forEach((q) => out.push(q.prompt));
      } catch { /* ignora */ }
    }
    return out;
  }
  const shortPrompt = (p) => String(p || '').replace(/\s+/g, ' ').trim().slice(0, 160);

  // Converte e valida a resposta; devolve { content, errors }.
  function parse(text, count) {
    const r = A.normalizeImport(text);
    if (r.errors.length) return { errors: r.errors };
    let raw;
    try { raw = A.extractJson(text); } catch { raw = {}; }
    const rawQs = Array.isArray(raw) ? raw : raw.questions || [];
    const errors = [];
    if (r.content.questions.length !== count) errors.push(`Pediste ${count} perguntas e vieram ${r.content.questions.length}.`);
    // Todas as imagens pedidas ficam (o enunciado já conta com elas); o máximo é só uma indicação no prompt.
    r.content.questions.forEach((q, i) => {
      const req = rawQs[i]?.imageRequest;
      if (req && typeof req === 'object' && typeof req.description === 'string' && req.description.trim()) {
        q.imageRequest = { description: req.description.trim(), alt: String(req.alt || '').trim().slice(0, 300) };
      }
    });
    if (A.checkContent(r.content).errors.length) errors.push(...A.checkContent(r.content).errors.map((e) => e.text));
    return { content: r.content, errors, warnings: r.warnings };
  }

  function nextTitles(c, n) {
    const titles = [];
    const used = new Set(A.state.worksheets.filter((w) => w.subjectId === c.subjectId && w.latest?.schoolYear === c.schoolYear).map((w) => A.norm(w.title)));
    let k = 1;
    while (titles.length < n) {
      const t = `${c.name} - ${String(k).padStart(2, '0')}`;
      if (!used.has(A.norm(t))) titles.push(t);
      k++;
    }
    return titles;
  }

  async function run(c, opts) {
    const subject = A.subject(c.subjectId)?.name || '', topic = A.topic(c.topicId)?.name || '';
    const titles = nextTitles(c, opts.plan.length);
    const job = { contentId: c.id, subjectId: c.subjectId, year: c.schoolYear, name: c.name, running: true,
      items: opts.plan.map((p, i) => ({ ...p, title: titles[i], state: 'pending' })) };
    jobs.unshift(job);
    refresh();
    try {
      const [freeMax, avoid] = await Promise.all([freeMaxQuestions(c), existingPrompts(c)]);
      let placeholderReady = false;
      for (const it of job.items) {
        it.state = 'running'; it.note = ''; refresh();
        try {
          if (it.tier === 'free' && it.count > freeMax) throw new Error(`Fichas Free têm no máximo ${freeMax} perguntas.`);
          const prompt = AI.buildPrompt({ subject, year: c.schoolYear, topic, content: c.name, semester: c.semester, tier: it.tier,
            count: it.count, title: it.title, avoid: avoid.slice(-80).map(shortPrompt), extra: opts.extra, maxImages: opts.maxImages });
          const onWait = (s) => { it.note = `à espera do limite por minuto (${s} s)…`; refresh(); };
          const onRetry = (s, n, max) => { it.note = `modelo sobrecarregado no Google; nova tentativa ${n}/${max} daqui a ${s} s…`; refresh(); };
          let res = await A.gemini.generate(prompt, { onWait, onRetry });
          let parsed = parse(res.text, it.count);
          if (parsed.errors.length) { // uma nova tentativa com os erros
            it.note = 'resposta com erros, a pedir de novo…'; refresh();
            res = await A.gemini.generate(`${prompt}\n\nA tua resposta anterior tinha estes erros; corrige-os e responde de novo só com o JSON:\n- ${parsed.errors.slice(0, 15).join('\n- ')}`, { onWait, onRetry });
            parsed = parse(res.text, it.count);
            if (parsed.errors.length) throw new Error('Resposta inválida do Gemini: ' + parsed.errors.slice(0, 3).join(' '));
          }
          const content = parsed.content;
          const imgQs = content.questions.filter((q) => q.imageRequest);
          if (imgQs.length) {
            if (!placeholderReady) { await A.ensurePlaceholderImage(); placeholderReady = true; }
            imgQs.forEach((q) => { q.image = { path: A.PLACEHOLDER_IMAGE, ...(q.imageRequest.alt ? { alt: q.imageRequest.alt } : {}) }; });
          }
          const publish = opts.publish && !imgQs.length;
          const args = { p_worksheet_id: null, p_subject_id: c.subjectId, p_school_year: c.schoolYear, p_topic_ids: [c.topicId],
            p_title: it.title, p_content: A.cleanContent(content), p_publish: false };
          const saved = await A.rpc('admin_save_worksheet', args);
          it.id = saved.worksheetId;
          if (it.tier === 'free') await A.rpc('admin_set_worksheet_tier', { p_id: saved.worksheetId, p_tier: 'free' });
          if (!A.state.contentsMissing) await A.rpc('admin_set_worksheet_contents', { p_worksheet_id: saved.worksheetId, p_content_ids: [c.id] });
          if (publish) await A.rpc('admin_save_worksheet', { ...args, p_worksheet_id: saved.worksheetId, p_publish: true });
          it.state = 'ok'; it.published = publish; it.images = imgQs.length; it.questions = content.questions.length;
          it.note = imgQs.length && opts.publish ? 'em rascunho até trocares as imagens provisórias' : '';
          content.questions.forEach((q) => avoid.push(q.prompt));
        } catch (e) {
          it.state = 'error'; it.note = e.message;
          if (e.status === 429 || e.overloaded || /Limite diário/.test(e.message)) { // sem quota ou modelo em baixo: parar
            job.items.filter((x) => x.state === 'pending').forEach((x) => { x.state = 'error'; x.note = e.overloaded ? 'não gerada (modelo sobrecarregado)' : 'não gerada (limite do Gemini)'; });
            break;
          }
        }
        refresh();
      }
    } catch (e) { A.fail(e); }
    job.running = false;
    await A.app.reload();
    const ok = job.items.filter((x) => x.state === 'ok').length;
    A.toast(ok === job.items.length ? 'ok' : 'warn', `${ok} de ${job.items.length} ficha(s) gerada(s) para «${esc(c.name)}».`, 6000);
  }

  // ---------- Painel na Cobertura ----------
  function refresh() { const el = $('aiGenPanel'); if (el) el.innerHTML = panelInner(A.coverage.current()); }

  function panelInner(open) {
    const list = open ? jobs.filter((j) => j.subjectId === open.subjectId && j.year === open.year) : [];
    if (!list.length) return '';
    return `<div class="ai-panel"><div class="row"><b>✨ Fichas geradas com IA</b><span class="spacer"></span>
        ${list.some((j) => j.running) ? '' : '<button class="sm ghost" data-ai-clear="1">Limpar</button>'}</div>` +
      list.map((j) => `<div class="ai-job"><div class="small"><b>${esc(j.name)}</b>${j.running ? ' <span class="badge warn">a gerar…</span>' : ''}</div>
        <ul>${j.items.map((it) => `<li>
          ${it.state === 'ok' ? '✅' : it.state === 'error' ? '❌' : it.state === 'running' ? '⏳' : '•'}
          ${it.id ? `<a href="#" data-act="edit-ws" data-id="${it.id}">${esc(it.title)}</a>` : esc(it.title)}
          <span class="badge ${it.tier === 'free' ? 'ok' : 'premium'}">${it.tier === 'free' ? 'Free' : '★ Premium'}</span>
          <span class="badge grey">${it.questions || it.count} perguntas</span>
          ${it.state === 'ok' ? (it.published ? '<span class="badge ok">Publicada</span>' : '<span class="badge warn">Rascunho</span>') : ''}
          ${it.images ? `<span class="badge warn">🖼 ${it.images} imagem(ns) a criar</span>` : ''}
          ${it.note ? `<span class="small ${it.state === 'error' ? 'q-err' : 'muted'}" style="display:inline">${esc(it.note)}</span>` : ''}
        </li>`).join('')}</ul></div>`).join('') + '</div>';
  }

  AI.panelHtml = (open) => `<div id="aiGenPanel">${panelInner(open)}</div>`;
  AI.clear = (open) => {
    for (let i = jobs.length - 1; i >= 0; i--) if (!jobs[i].running && open && jobs[i].subjectId === open.subjectId && jobs[i].year === open.year) jobs.splice(i, 1);
    refresh();
  };
})();
