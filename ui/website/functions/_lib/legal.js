// Páginas legais renderizadas no servidor (Cloudflare Pages Functions).
// A fonte de verdade é a Edge Function `legal` do Supabase: a versão em vigor de
// cada tipo é publicada no painel de administração (tools/admin) e aparece aqui
// sem novo deploy do site. Pedidos servidor-a-servidor não enviam `Origin`,
// por isso não é preciso acrescentar o site ao ALLOWED_ORIGINS.

const LEGAL_API = 'https://hhgxxvvreyhigxynrgmv.supabase.co/functions/v1/legal/v1/documents';
const SITE = 'https://escolaemdia.me';
const CACHE_SECONDS = 600; // 10 min na edge; versões novas aparecem rapidamente

export const PAGES = {
  privacy: { path: '/politica-de-privacidade', label: 'Política de Privacidade' },
  terms: { path: '/termos-e-condicoes', label: 'Termos e Condições' },
};

const esc = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const slug = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60);

// Markdown simples, como definido na API: #, ##, ###, listas «-», «---» e **negrito**.
// Tudo é escapado antes; URLs e e-mails passam a ligações.
function inline(text) {
  let h = esc(text);
  h = h.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  h = h.replace(/\bhttps?:\/\/[^\s<]+[^\s<.,;:!?)»]/g, (u) => `<a href="${u}" rel="noopener">${u}</a>`);
  h = h.replace(/(^|[\s(«])([a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,})(?=[\s.,;:)»]|$)/gi,
    (_, pre, mail) => `${pre}<a href="mailto:${mail}">${mail}</a>`);
  return h;
}

export function renderMarkdown(md) {
  const lines = md.replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  const toc = [];
  let title = null;
  let para = [];
  let list = null;
  const used = new Set();
  const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para = []; } };
  const flushList = () => { if (list) { out.push(`<ul>${list.map((li) => `<li>${inline(li)}</li>`).join('')}</ul>`); list = null; } };
  const flush = () => { flushPara(); flushList(); };

  for (const raw of lines) {
    const line = raw.trim();
    let m;
    if (!line) { flush(); continue; }
    if ((m = /^(#{1,3})\s+(.*)$/.exec(line))) {
      flush();
      const level = m[1].length;
      const text = m[2].trim();
      if (level === 1 && !title) { title = text; continue; }
      const tag = level === 1 ? 'h2' : `h${level}`;
      let id = slug(text) || 'seccao';
      while (used.has(id)) id += '-';
      used.add(id);
      if (tag === 'h2') toc.push({ id, text });
      out.push(`<${tag} id="${id}">${inline(text)}</${tag}>`);
      continue;
    }
    if (/^(-{3,}|\*{3,})$/.test(line)) { flush(); out.push('<hr>'); continue; }
    if ((m = /^[-*]\s+(.*)$/.exec(line))) { flushPara(); (list ||= []).push(m[1]); continue; }
    flushList();
    para.push(line);
  }
  flush();
  return { title, html: out.join('\n'), toc };
}

const fmtDate = (iso) => {
  try {
    return new Intl.DateTimeFormat('pt-PT', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Lisbon' }).format(new Date(iso));
  } catch { return iso.slice(0, 10); }
};

async function fetchDocuments() {
  const res = await fetch(LEGAL_API, {
    headers: { accept: 'application/json' },
    cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true },
  });
  if (!res.ok) throw new Error(`legal API ${res.status}`);
  const data = await res.json();
  return Array.isArray(data.items) ? data.items : [];
}

function layout({ title, description, canonical, body, status = 200, robots = 'index, follow' }) {
  const html = `<!DOCTYPE html>
<html lang="pt-PT">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${esc(title)}</title>
  <meta name="description" content="${esc(description)}">
  <meta name="robots" content="${robots}">
  <meta name="theme-color" content="#5845CA">
  ${canonical ? `<link rel="canonical" href="${canonical}">` : ''}
  <link rel="icon" type="image/png" sizes="64x64" href="/favicon.png">
  <link rel="apple-touch-icon" sizes="192x192" href="/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <meta property="og:type" content="article">
  <meta property="og:locale" content="pt_PT">
  <meta property="og:site_name" content="Escola em Dia">
  <meta property="og:title" content="${esc(title)}">
  <meta property="og:description" content="${esc(description)}">
  ${canonical ? `<meta property="og:url" content="${canonical}">` : ''}
  <meta property="og:image" content="${SITE}/og-image.png">
  <link rel="preload" href="/fonts/lexend-latin.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="/styles.css">
  <script src="/consent.js"></script>
</head>
<body>
  <header class="header is-scrolled is-static">
    <div class="container header__inner">
      <a class="brand" href="/" aria-label="Escola em Dia — início">
        <img src="/apple-touch-icon.png" alt="" width="36" height="36">
        <span>Escola em Dia</span>
      </a>
      <div class="header__actions">
        <a class="link-login" href="https://app.escolaemdia.me/?modo=entrar">Entrar</a>
        <a class="btn btn--primary btn--sm" href="https://app.escolaemdia.me/">Criar conta</a>
      </div>
    </div>
  </header>
  <main>
${body}
  </main>
  <footer class="footer">
    <div class="container footer__inner">
      <a class="brand brand--sm" href="/">
        <img src="/apple-touch-icon.png" alt="" width="28" height="28">
        <span>Escola em Dia</span>
      </a>
      <nav aria-label="Rodapé">
        <a href="/termos-e-condicoes">Termos e Condições</a>
        <a href="/politica-de-privacidade">Política de Privacidade</a>
        <a href="/cookies">Política de cookies</a>
        <button type="button" class="footer__cookies" data-cookie-settings>Preferências de cookies</button>
        <a href="https://www.livroreclamacoes.pt/" rel="noopener">Livro de Reclamações</a>
      </nav>
      <small>© ${new Date().getFullYear()} Escola em Dia · Feito em Portugal</small>
    </div>
  </footer>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': status === 200 ? `public, max-age=300, s-maxage=${CACHE_SECONDS}` : 'no-store',
    },
  });
}

export async function renderLegalPage(kind) {
  const page = PAGES[kind];
  const canonical = SITE + page.path;
  let doc;
  try {
    doc = (await fetchDocuments()).find((d) => d.kind === kind);
  } catch (err) {
    console.error('legal fetch failed', err);
  }

  if (!doc) {
    return layout({
      title: `${page.label} — Escola em Dia`,
      description: `${page.label} da Escola em Dia.`,
      canonical,
      status: 503,
      robots: 'noindex, follow',
      body: `    <section class="notfound container">
      <div class="notfound__emoji" aria-hidden="true">📄</div>
      <h1>Não conseguimos carregar o documento.</h1>
      <p>Tenta novamente daqui a pouco. Também o podes consultar na aplicação, no menu da conta, em «Documentos legais».</p>
      <div class="hero__ctas" style="justify-content:center">
        <a class="btn btn--primary btn--lg" href="${page.path}">Tentar novamente</a>
        <a class="btn btn--ghost btn--lg" href="/">Voltar ao início</a>
      </div>
    </section>`,
    });
  }

  const { title, html, toc } = renderMarkdown(doc.content);
  const pageTitle = title || doc.title || page.label;
  const other = kind === 'privacy' ? PAGES.terms : PAGES.privacy;
  const tocHtml = toc.length > 2
    ? `<nav class="doc__toc" aria-label="Índice"><strong>Índice</strong><ul>${toc.map((t) => `<li><a href="#${t.id}">${inline(t.text)}</a></li>`).join('')}</ul></nav>`
    : '';

  return layout({
    title: `${page.label} — Escola em Dia`,
    description: `${page.label} da Escola em Dia, a aplicação de apoio ao estudo em família para crianças do 1.º ao 9.º ano. Versão ${doc.version}, em vigor desde ${fmtDate(doc.publishedAt)}.`,
    canonical,
    body: `    <article class="doc doc--legal container container--narrow">
      <p class="eyebrow">Documento legal</p>
      <h1>${inline(pageTitle)}</h1>
      <p class="doc__meta">Versão ${esc(doc.version)} · em vigor desde ${esc(fmtDate(doc.publishedAt))}${doc.changeSummary ? ` · ${inline(doc.changeSummary)}` : ''}</p>
      ${tocHtml}
      <div class="doc__body">
${html}
      </div>
      <aside class="doc__note">
        <p>Esta é a versão em vigor. As versões que aceitaste ficam disponíveis na aplicação, no menu da conta, em «Documentos legais».</p>
        <p><a href="${other.path}">Ler também: ${other.label}</a></p>
      </aside>
    </article>`,
  });
}
