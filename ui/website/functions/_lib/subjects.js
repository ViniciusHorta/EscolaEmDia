// Disciplinas do site lidas da base de dados (função SQL `site_subjects`): só as que têm
// fichas publicadas, com os anos em que existem. Pedido servidor-a-servidor com a chave
// pública (a mesma da app), em cache na edge; se falhar, a página estática fica como está.

const SUPABASE_URL = 'https://hhgxxvvreyhigxynrgmv.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_7cBwufZF1sDnn_tUEJm57A_i0pCVDCF';
const CACHE_SECONDS = 600; // 10 min, como as páginas legais

const CYCLES = [
  { label: '1.º ciclo', years: [1, 2, 3, 4] },
  { label: '2.º ciclo', years: [5, 6] },
  { label: '3.º ciclo', years: [7, 8, 9] },
];

const FAQ_QUESTION = 'Que disciplinas há?';

const esc = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** «A», «A e B», «A, B e C». */
const joinPt = (items) => items.length < 2 ? items.join('') : `${items.slice(0, -1).join(', ')} e ${items.at(-1)}`;

/** [{ name, years }] ou null se não for possível obter a lista. */
export async function fetchSubjects() {
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/site_subjects`, {
      headers: { apikey: PUBLISHABLE_KEY, accept: 'application/json' },
      cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (!Array.isArray(data)) throw new Error('resposta inválida');
    const subjects = data
      .filter((s) => s && typeof s.name === 'string' && s.name.trim() && Array.isArray(s.years))
      .map((s) => ({ name: s.name.trim(), years: s.years.map(Number) }));
    return subjects.length ? subjects : null;
  } catch (err) {
    console.error('site_subjects fetch failed', err);
    return null;
  }
}

/** Resposta à pergunta «Que disciplinas há?», agrupada por ciclo. */
export function subjectsAnswer(subjects) {
  const parts = [];
  const missing = [];
  for (const cycle of CYCLES) {
    const names = subjects.filter((s) => s.years.some((y) => cycle.years.includes(y))).map((s) => s.name);
    if (names.length) parts.push(`${cycle.label}: ${joinPt(names)}`);
    else missing.push(cycle.label.replace(' ciclo', ''));
  }
  const intro = parts.length === 1 ? `No ${parts[0]}.` : `${parts.join('; ')}.`;
  const next = missing.length
    ? ` Estamos a acrescentar fichas e disciplinas, também para o ${joinPt(missing)} ${missing.length > 1 ? 'ciclos' : 'ciclo'}.`
    : ' Estamos a acrescentar novas fichas e disciplinas.';
  return intro + next;
}

/** Atualiza a FAQ (página e dados estruturados) e o campo `teaches` do index.html. */
export function applyToIndex(html, subjects) {
  const answer = subjectsAnswer(subjects);
  let out = html.replace(/(<p data-subjects-answer>)[\s\S]*?(<\/p>)/, (_, open, close) => `${open}${esc(answer)}${close}`);
  out = out.replace(/(<script type="application\/ld\+json">)([\s\S]*?)(<\/script>)/, (whole, open, json, close) => {
    try {
      const data = JSON.parse(json);
      for (const node of data['@graph'] ?? []) {
        if (Array.isArray(node.teaches)) node.teaches = subjects.map((s) => s.name);
        if (node['@type'] === 'FAQPage') {
          const q = (node.mainEntity ?? []).find((e) => e.name === FAQ_QUESTION);
          if (q?.acceptedAnswer) q.acceptedAnswer.text = answer;
        }
      }
      return `${open}\n${JSON.stringify(data, null, 2).replace(/</g, '\\u003c')}\n  ${close}`;
    } catch {
      return whole;
    }
  });
  return out;
}

/** Atualiza as linhas de disciplinas do llms.txt. */
export function applyToLlms(text, subjects) {
  const answer = subjectsAnswer(subjects);
  return text
    .replace(/^- Disciplinas: .*$/m, `- Disciplinas: ${answer}`)
    .replace(/^- \*\*Que disciplinas há\?\*\* .*$/m, `- **Que disciplinas há?** ${answer}`);
}
