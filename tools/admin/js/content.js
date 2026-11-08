// Conteúdo das fichas: validação (espelha public.valid_worksheet_content), pedido para a IA e pré-visualização.
(() => {
  'use strict';
  const A = window.A, esc = A.esc;

  A.typeLabel = { 'multiple-choice': 'Escolha múltipla', 'true_false': 'Verdadeiro ou falso', 'written': 'Resposta aberta' };
  A.typeShort = { 'multiple-choice': 'EM', 'true_false': 'V/F', 'written': 'Aberta' };

  // ---------- Validação estrita (editor) ----------
  // Devolve { errors: [{ q: índice|null, text }] } com as mesmas regras da base de dados.
  A.checkContent = (content) => {
    const errors = [];
    const add = (q, text) => errors.push({ q, text });
    const qs = content && content.questions;
    if (!Array.isArray(qs)) { add(null, '"questions" tem de ser uma lista.'); return { errors }; }
    if (qs.length < 1) add(null, 'A ficha precisa de pelo menos uma pergunta.');
    if (qs.length > 50) add(null, `A ficha tem ${qs.length} perguntas; o máximo é 50.`);
    for (const key of ['instructions', 'text']) {
      if (content[key] != null && typeof content[key] !== 'string') add(null, `"${key}" tem de ser texto.`);
    }
    const ids = new Set();
    qs.forEach((q, i) => {
      if (!q || typeof q !== 'object' || Array.isArray(q)) { add(i, 'Pergunta inválida.'); return; }
      if (typeof q.id !== 'string' || !q.id.trim()) add(i, 'Sem identificador.');
      else if (ids.has(q.id)) add(i, `Identificador "${q.id}" repetido.`);
      ids.add(q.id);
      if (typeof q.prompt !== 'string' || !q.prompt.trim()) add(i, 'Falta o enunciado.');
      if (!A.typeLabel[q.type]) add(i, 'Tipo de pergunta inválido.');
      if (q.type === 'multiple-choice') {
        if (!Array.isArray(q.options)) { add(i, 'Faltam as opções.'); return; }
        if (q.options.length < 2 || q.options.length > 8) add(i, `Tem ${q.options.length} opções; são precisas entre 2 e 8.`);
        const optIds = new Set();
        q.options.forEach((o, j) => {
          if (!o || typeof o.id !== 'string' || !o.id.trim() || optIds.has(o.id)) add(i, `Opção ${j + 1} com identificador inválido ou repetido.`);
          if (o) optIds.add(o.id);
          if (!o || typeof o.text !== 'string' || !o.text.trim()) add(i, `A opção ${String.fromCharCode(65 + j)} está vazia.`);
        });
        if (typeof q.correctAnswer !== 'string' || !optIds.has(q.correctAnswer)) add(i, 'Marca a opção certa.');
      } else if (q.type === 'true_false') {
        if (typeof q.correctAnswer !== 'boolean') add(i, 'Escolhe se a afirmação é verdadeira ou falsa.');
        if ('options' in q) add(i, 'Verdadeiro/falso não pode ter "options".');
      }
      if (q.explanation != null && typeof q.explanation !== 'string') add(i, '"explanation" tem de ser texto.');
    });
    return { errors };
  };

  // Limpa espaços e campos vazios antes de gravar (preserva campos desconhecidos, ex.: topicId, audioText).
  A.cleanContent = (content) => {
    const out = { ...content };
    for (const key of ['instructions', 'text']) {
      if (typeof out[key] === 'string') { out[key] = out[key].trim(); if (!out[key]) delete out[key]; }
    }
    out.questions = content.questions.map((q) => {
      const c = { ...q, id: q.id.trim(), prompt: q.prompt.trim() };
      if (typeof c.explanation === 'string') { c.explanation = c.explanation.trim(); if (!c.explanation) delete c.explanation; }
      if (c.type === 'multiple-choice') c.options = c.options.map((o) => ({ ...o, text: o.text.trim() }));
      if (c.type === 'written') { delete c.options; delete c.correctAnswer; }
      if (c.type === 'true_false') delete c.options;
      return c;
    });
    return out;
  };

  // ---------- Importação tolerante (JSON vindo da IA) ----------
  const typeAliases = { 'multiple_choice': 'multiple-choice', 'multiplechoice': 'multiple-choice', 'escolha-multipla': 'multiple-choice',
    'true-false': 'true_false', 'truefalse': 'true_false', 'verdadeiro_falso': 'true_false', 'verdadeiro-falso': 'true_false',
    'open': 'written', 'aberta': 'written', 'text': 'written' };

  A.extractJson = (raw) => {
    const text = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '').trim();
    const first = Math.min(...['{', '['].map((c) => { const i = text.indexOf(c); return i < 0 ? Infinity : i; }));
    if (first === Infinity) throw new Error('Não encontrei JSON no texto colado.');
    const last = Math.max(text.lastIndexOf('}'), text.lastIndexOf(']'));
    return JSON.parse(text.slice(first, last + 1));
  };

  // Converte o JSON da IA no formato da base, corrigindo pequenos desvios (com avisos).
  A.normalizeImport = (raw) => {
    const errors = [], warnings = [];
    let data;
    try { data = A.extractJson(raw); } catch (e) { return { errors: ['JSON inválido: ' + e.message], warnings }; }
    if (Array.isArray(data)) { data = { questions: data }; warnings.push('Recebi uma lista: tratei-a como "questions".'); }
    if (!data || typeof data !== 'object') return { errors: ['A raiz do JSON tem de ser um objeto.'], warnings };
    const content = {};
    for (const key of ['instructions', 'text']) {
      if (data[key] == null) continue;
      if (typeof data[key] !== 'string') errors.push(`"${key}" tem de ser texto.`);
      else if (data[key].trim()) content[key] = data[key].trim();
    }
    const title = typeof data.title === 'string' ? data.title.trim() : '';
    const qs = data.questions;
    if (!Array.isArray(qs)) return { errors: [...errors, '"questions" tem de ser uma lista.'], warnings };
    if (qs.length < 1 || qs.length > 50) errors.push(`"questions" tem ${qs.length} perguntas; o permitido é entre 1 e 50.`);
    const ids = new Set();
    content.questions = qs.map((q, i) => {
      const n = `Pergunta ${i + 1}`;
      if (!q || typeof q !== 'object' || Array.isArray(q)) { errors.push(`${n}: tem de ser um objeto.`); return q; }
      const out = {};
      let id = typeof q.id === 'string' || typeof q.id === 'number' ? String(q.id).trim() : '';
      if (!id) { id = `q${i + 1}`; warnings.push(`${n}: sem "id"; atribuí "${id}".`); }
      if (ids.has(id)) errors.push(`${n}: o id "${id}" está repetido.`);
      ids.add(id); out.id = id;
      let type = typeof q.type === 'string' ? q.type.trim() : '';
      if (typeAliases[type.toLowerCase()]) { warnings.push(`${n}: tipo "${type}" convertido em "${typeAliases[type.toLowerCase()]}".`); type = typeAliases[type.toLowerCase()]; }
      if (!A.typeLabel[type]) errors.push(`${n}: "type" tem de ser multiple-choice, true_false ou written.`);
      out.type = type;
      if (typeof q.prompt !== 'string' || !q.prompt.trim()) errors.push(`${n}: "prompt" em falta ou vazio.`);
      else out.prompt = q.prompt.trim();

      if (type === 'multiple-choice') {
        if (!Array.isArray(q.options)) errors.push(`${n}: "options" tem de ser uma lista.`);
        else {
          if (q.options.length < 2 || q.options.length > 8) errors.push(`${n}: tem ${q.options.length} opções; o permitido é entre 2 e 8.`);
          const optionIds = new Set();
          out.options = q.options.map((o, j) => {
            if (typeof o === 'string') o = { text: o };
            const optId = o && (typeof o.id === 'string' || typeof o.id === 'number') && String(o.id).trim() ? String(o.id).trim() : String.fromCharCode(97 + j);
            if (optionIds.has(optId)) errors.push(`${n}: a opção "${optId}" está repetida.`);
            optionIds.add(optId);
            if (!o || typeof o.text !== 'string' || !o.text.trim()) errors.push(`${n}: a opção ${j + 1} não tem "text".`);
            return { id: optId, text: o && typeof o.text === 'string' ? o.text.trim() : '' };
          });
          let correct = q.correctAnswer;
          if (typeof correct === 'number' && out.options[correct]) { correct = out.options[correct].id; warnings.push(`${n}: "correctAnswer" numérico convertido no id "${correct}".`); }
          if (typeof correct !== 'string' || !optionIds.has(correct)) errors.push(`${n}: "correctAnswer" tem de ser o id de uma das opções (${[...optionIds].join(', ')}).`);
          out.correctAnswer = correct;
        }
      } else if (type === 'true_false') {
        let correct = q.correctAnswer;
        if (typeof correct === 'string' && /^(true|verdadeiro|v)$/i.test(correct.trim())) { correct = true; warnings.push(`${n}: "correctAnswer" em texto convertido em true.`); }
        if (typeof correct === 'string' && /^(false|falso|f)$/i.test(correct.trim())) { correct = false; warnings.push(`${n}: "correctAnswer" em texto convertido em false.`); }
        if (typeof correct !== 'boolean') errors.push(`${n}: "correctAnswer" tem de ser true ou false.`);
        if ('options' in q) warnings.push(`${n}: "options" ignorado em verdadeiro/falso.`);
        out.correctAnswer = correct;
      } else if (type === 'written' && ('options' in q || 'correctAnswer' in q)) {
        warnings.push(`${n}: "options"/"correctAnswer" ignorados em resposta aberta.`);
      }
      if (q.explanation != null) {
        if (typeof q.explanation !== 'string') errors.push(`${n}: "explanation" tem de ser texto.`);
        else if (q.explanation.trim()) out.explanation = q.explanation.trim();
      } else if (type !== 'written') warnings.push(`${n}: sem "explanation" (recomendada para a correção da criança).`);
      return out;
    });
    const tf = content.questions.filter((q) => q && q.type === 'true_false');
    if (tf.length >= 3 && tf.every((q) => q.correctAnswer === tf[0].correctAnswer)) warnings.push('Todas as perguntas verdadeiro/falso têm a mesma resposta.');
    return { errors, warnings, content, title };
  };

  // ---------- Pedido para a IA ----------
  A.schemaDoc = `{
  "title": "Título curto da ficha (até 160 caracteres)",
  "instructions": "Instrução geral para a criança (opcional)",
  "questions": [
    {
      "id": "q1",
      "type": "multiple-choice",
      "prompt": "Enunciado da pergunta",
      "options": [
        { "id": "a", "text": "Opção A" },
        { "id": "b", "text": "Opção B" },
        { "id": "c", "text": "Opção C" }
      ],
      "correctAnswer": "b",
      "explanation": "Explicação curta mostrada à criança na correção"
    },
    {
      "id": "q2",
      "type": "true_false",
      "prompt": "Afirmação para a criança decidir se é verdadeira ou falsa",
      "correctAnswer": true,
      "explanation": "Explicação curta"
    },
    {
      "id": "q3",
      "type": "written",
      "prompt": "Pergunta de resposta aberta",
      "explanation": "Resposta esperada e critérios para os responsáveis (não é mostrada à criança)"
    }
  ]
}

Regras validadas pela base de dados:
• "questions": entre 1 e 50 perguntas; cada "id" é único e não vazio; "prompt" não vazio.
• "type": "multiple-choice", "true_false" ou "written".
• multiple-choice: "options" com 2 a 8 opções, cada uma com "id" único e "text" não vazio;
  "correctAnswer" é o "id" (texto) de uma das opções.
• true_false: "correctAnswer" é true ou false (booleano, sem aspas) e não tem "options".
• written: sem "options" nem "correctAnswer"; corrigida pelos responsáveis no Painel do Responsável.
• "explanation" é opcional mas recomendada.`;

  A.buildAiPrompt = ({ year, subject, topics, counts, extra, title }) => {
    const total = counts.mc + counts.tf + counts.wr;
    const topicText = topics.length ? topics.map((t) => `«${t}»`).join(' e ') : '(tema)';
    return `És um professor do ${Number(year) >= 7 ? '3.º' : Number(year) >= 5 ? '2.º' : '1.º'} Ciclo do Ensino Básico em Portugal. Cria uma ficha de exercícios para uma criança do ${year}.º ano, na disciplina de ${subject || '(disciplina)'}, sobre ${topics.length > 1 ? 'os temas' : 'o tema'} ${topicText}, alinhada com as Aprendizagens Essenciais.${title ? `\nTítulo pretendido: «${title}».` : ''}

Composição (exatamente ${total} perguntas):
• ${counts.mc} de escolha múltipla ("multiple-choice") com 3 ou 4 opções e uma só resposta certa;
• ${counts.tf} de verdadeiro ou falso ("true_false");
• ${counts.wr} de resposta aberta ("written"), que a criança pode responder por escrito ou no caderno.
${extra ? `\nIndicações adicionais: ${extra}\n` : ''}
Regras de conteúdo:
• Português de Portugal (pt-PT), frases curtas e claras, adequadas à idade (${Number(year) + 5}–${Number(year) + 6} anos).
• Varia a posição da resposta certa nas perguntas de escolha múltipla; opções erradas plausíveis.
• Equilibra as respostas verdadeiro/falso (não ponhas todas iguais).
• Sem dados pessoais, marcas, violência ou temas sensíveis.
• "explanation": explicação curta e encorajadora para a criança (escolha múltipla e verdadeiro/falso); nas abertas, a resposta esperada e os critérios para os responsáveis.
• Começa com uma "instructions" curta e amigável para a criança.

Formato: responde APENAS com um único objeto JSON válido, sem texto antes ou depois e sem comentários, exatamente com esta estrutura:

${A.schemaDoc}`;
  };

  // ---------- Pré-visualização ----------
  A.renderQuestionBody = (q) => {
    let html = `<div class="prompt">${esc(q.prompt || '')}</div>`;
    if (q.type === 'multiple-choice' && Array.isArray(q.options)) html += `<ol type="a">` + q.options.map((o) =>
      `<li class="${o.id === q.correctAnswer ? 'correct' : ''}">${esc(o.text)}${o.id === q.correctAnswer ? ' ✓' : ''}</li>`).join('') + `</ol>`;
    if (q.type === 'true_false') html += `<div style="margin-top:6px">Resposta certa: <b style="color:var(--success)">${q.correctAnswer === true ? 'Verdadeiro' : q.correctAnswer === false ? 'Falso' : '—'}</b></div>`;
    if (q.explanation) html += `<div class="exp">💡 ${esc(q.explanation)}</div>`;
    return html;
  };
  A.countByType = (questions) => questions.reduce((acc, q) => (acc[q.type] = (acc[q.type] || 0) + 1, acc), {});
  A.renderPreview = (content) => {
    const counts = A.countByType(content.questions || []);
    let html = `<div class="row">` + Object.entries(counts).map(([t, c]) => `<span class="badge">${c} × ${esc(A.typeLabel[t] || t)}</span>`).join('') + `</div>`;
    if (content.instructions) html += `<p class="hint" style="margin:10px 0 0"><b>Instruções:</b> ${esc(content.instructions)}</p>`;
    if (content.text) html += `<p class="hint" style="margin:6px 0 0; white-space:pre-wrap"><b>Texto:</b> ${esc(content.text)}</p>`;
    (content.questions || []).forEach((q, i) => {
      html += `<div class="pv-q"><div class="row" style="margin-bottom:4px"><span class="badge">${i + 1}</span><span class="badge ok">${esc(A.typeLabel[q.type] || q.type)}</span></div>${A.renderQuestionBody(q)}</div>`;
    });
    return html;
  };
})();
