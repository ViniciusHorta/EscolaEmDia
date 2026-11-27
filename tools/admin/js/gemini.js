// Gemini (Google AI): token, modelo e limites guardados só neste navegador (localStorage); chamadas à API;
// contagem de uso (a API não diz quanto falta da quota, por isso o admin conta os pedidos que faz daqui).
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const G = A.gemini = {};
  const API = 'https://generativelanguage.googleapis.com/v1beta';
  const LS = { cfg: 'escolaemdia.admin.gemini', usage: 'escolaemdia.admin.gemini.usage' };
  const DEFAULTS = { token: '', model: 'gemini-3.8-flash', imageModel: 'gemini-2.5-flash-image', rpm: 10, rpd: 250 };

  const read = (k, fallback) => { try { return JSON.parse(localStorage.getItem(k)) ?? fallback; } catch { return fallback; } };
  const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* armazenamento bloqueado */ } };

  G.config = () => ({ ...DEFAULTS, ...read(LS.cfg, {}) });
  G.saveConfig = (patch) => { write(LS.cfg, { ...G.config(), ...patch }); G.renderBar(); };
  G.ready = () => !!G.config().token;

  // ---------- Uso ----------
  // A quota diária do Gemini recomeça à meia-noite do Pacífico.
  const dayKey = (t = Date.now()) => new Date(t).toLocaleDateString('en-CA', { timeZone: 'America/Los_Angeles' });
  let lastLimit = null; // { at, text } do último 429

  function usage() {
    const list = read(LS.usage, []);
    const cut = Date.now() - 2 * 86400000;
    return Array.isArray(list) ? list.filter((u) => u && u.t > cut) : [];
  }
  function record(entry) { const list = usage(); list.push({ t: Date.now(), ...entry }); write(LS.usage, list); }

  G.stats = () => {
    const list = usage(), now = Date.now(), today = dayKey();
    const day = list.filter((u) => dayKey(u.t) === today);
    return {
      minute: list.filter((u) => now - u.t < 60000).length,
      day: day.length,
      tokens: day.reduce((n, u) => n + (u.tokens || 0), 0),
      errors: day.filter((u) => u.error).length,
      oldestInMinute: list.filter((u) => now - u.t < 60000).reduce((m, u) => Math.min(m, u.t), now),
    };
  };

  const fmtK = (n) => n >= 1e6 ? (n / 1e6).toFixed(1) + ' M' : n >= 1000 ? Math.round(n / 1000) + ' mil' : String(n);
  const level = (n, max) => (max && n >= max ? 'err' : max && n >= max * 0.8 ? 'warn' : 'ok');

  // ---------- Barra superior ----------
  G.renderBar = () => {
    const bar = $('aiBar');
    if (!bar) return;
    bar.hidden = !G.ready();
    if (bar.hidden) return;
    const c = G.config(), s = G.stats();
    const limited = lastLimit && Date.now() - lastLimit.at < 5 * 60000;
    bar.innerHTML = `<button class="ai-bar-in" data-tab-link="gemini" title="Contado por este admin neste navegador (a API não informa a quota restante). Clica para configurar.">
      <b>✨ Gemini</b><span class="muted">${esc(c.model)}</span>
      <span class="badge ${level(s.minute, c.rpm)}">${s.minute}/${c.rpm || '∞'} por minuto</span>
      <span class="badge ${level(s.day, c.rpd)}">${s.day}/${c.rpd || '∞'} hoje</span>
      <span class="badge grey">${fmtK(s.tokens)} tokens hoje</span>
      ${limited ? `<span class="badge err">Limite atingido: ${esc(lastLimit.text)}</span>` : ''}
    </button>`;
  };

  // ---------- API ----------
  class GeminiError extends Error { constructor(msg, extra = {}) { super(msg); Object.assign(this, extra); } }

  async function call(path, { method = 'GET', body } = {}) {
    const { token } = G.config();
    if (!token) throw new GeminiError('Configura primeiro o token do Gemini (Configurações › Gemini).');
    let res;
    try {
      res = await fetch(`${API}/${path}`, { method, headers: { 'x-goog-api-key': token, 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined });
    } catch (e) { throw new GeminiError('Sem ligação ao Gemini (' + e.message + ').'); }
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const err = data?.error || {};
      const details = Array.isArray(err.details) ? err.details : [];
      const retry = details.find((d) => /RetryInfo/.test(d['@type'] || ''))?.retryDelay;
      const quota = details.find((d) => /QuotaFailure/.test(d['@type'] || ''))?.violations?.[0]?.quotaId;
      if (res.status === 429) {
        lastLimit = { at: Date.now(), text: [quota, retry && `tenta daqui a ${retry}`].filter(Boolean).join(' • ') || 'quota esgotada' };
        G.renderBar();
        throw new GeminiError(`Limite do Gemini atingido${quota ? ` (${quota})` : ''}.${retry ? ` Tenta daqui a ${retry}.` : ''}`, { status: 429, retry });
      }
      if (res.status === 400 && /API key/i.test(err.message || '')) throw new GeminiError('Token do Gemini inválido.', { status: 400 });
      if (res.status === 403) throw new GeminiError('O token do Gemini não tem acesso (' + (err.message || 'HTTP 403') + ').', { status: 403 });
      throw new GeminiError('Gemini: ' + (err.message || `HTTP ${res.status}`), { status: res.status });
    }
    return data;
  }

  G.listModels = async () => {
    const out = [];
    let page = '';
    do {
      const d = await call(`models?pageSize=200${page ? '&pageToken=' + encodeURIComponent(page) : ''}`);
      out.push(...(d.models || []));
      page = d.nextPageToken || '';
    } while (page);
    return out.filter((m) => (m.supportedGenerationMethods || []).includes('generateContent') && /gemini/i.test(m.name))
      .map((m) => ({ id: m.name.replace(/^models\//, ''), label: m.displayName || m.name }));
  };

  // Espera se o limite por minuto configurado já foi atingido (evita 429 em lotes).
  async function throttle(onWait) {
    const c = G.config();
    for (;;) {
      const s = G.stats();
      if (c.rpd && s.day >= c.rpd) throw new GeminiError(`Limite diário configurado atingido (${s.day}/${c.rpd} pedidos hoje). Recomeça à meia-noite do Pacífico (8h em Lisboa).`);
      if (!c.rpm || s.minute < c.rpm) return;
      const wait = Math.max(1000, 60000 - (Date.now() - s.oldestInMinute) + 500);
      onWait?.(Math.ceil(wait / 1000));
      await new Promise((r) => setTimeout(r, Math.min(wait, 5000)));
    }
  }

  // Gera texto (JSON) a partir de um prompt. Devolve { text, usage }.
  // Modelo sobrecarregado (503) ou erro temporário do servidor: tenta de novo com esperas crescentes.
  const RETRY_DELAYS = [10, 30, 60, 120]; // segundos
  const temporary = (e) => [500, 502, 503, 504].includes(e.status);

  // Um pedido generateContent com limite por minuto e novas tentativas em erros temporários.
  async function generateContent(model, body, { onWait, onRetry } = {}) {
    for (let attempt = 0; ; attempt++) {
      await throttle(onWait);
      try {
        const data = await call(`models/${encodeURIComponent(model)}:generateContent`, { method: 'POST', body });
        record({ tokens: data.usageMetadata?.totalTokenCount || 0 });
        G.renderBar();
        return data;
      } catch (e) {
        record({ error: true });
        G.renderBar();
        if (!temporary(e)) throw e;
        if (attempt >= RETRY_DELAYS.length) {
          throw new GeminiError(`O modelo ${model} está sobrecarregado no Google (tentei ${attempt + 1} vezes). Tenta mais tarde ou escolhe outro modelo em Configurações › Gemini.`, { status: e.status, overloaded: true });
        }
        const wait = RETRY_DELAYS[attempt];
        for (let s = wait; s > 0; s -= 5) {
          onRetry?.(s, attempt + 1, RETRY_DELAYS.length);
          await new Promise((r) => setTimeout(r, Math.min(5, s) * 1000));
        }
      }
    }
  }

  const noContent = (data, cand) => new GeminiError(`O Gemini não devolveu conteúdo (${data.promptFeedback?.blockReason || cand?.finishReason || 'sem resposta'}).`);

  G.generate = async (prompt, { onWait, onRetry, temperature = 0.8 } = {}) => {
    const data = await generateContent(G.config().model, {
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: 'application/json', temperature },
    }, { onWait, onRetry });
    const cand = data.candidates?.[0];
    const text = (cand?.content?.parts || []).map((p) => p.text || '').join('');
    if (!text) throw noContent(data, cand);
    if (cand.finishReason === 'MAX_TOKENS') throw new GeminiError('A resposta do Gemini foi cortada (limite de tamanho). Tenta com menos perguntas.');
    return { text, usage: data.usageMetadata || {} };
  };

  // Gera uma imagem quadrada com o modelo de imagens. Devolve um Blob (PNG/JPEG/WebP).
  G.generateImage = async (prompt, { onWait, onRetry } = {}) => {
    const { imageModel } = G.config();
    const data = await generateContent(imageModel, {
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['TEXT', 'IMAGE'], imageConfig: { aspectRatio: '1:1' } },
    }, { onWait, onRetry });
    const cand = data.candidates?.[0];
    const part = (cand?.content?.parts || []).find((p) => (p.inlineData || p.inline_data)?.data);
    if (!part) {
      const said = (cand?.content?.parts || []).map((p) => p.text || '').join(' ').trim();
      if (said) throw new GeminiError('O Gemini não gerou imagem: ' + said.slice(0, 300));
      throw noContent(data, cand);
    }
    const inline = part.inlineData || part.inline_data;
    const bytes = Uint8Array.from(atob(inline.data), (c) => c.charCodeAt(0));
    return new Blob([bytes], { type: inline.mimeType || inline.mime_type || 'image/png' });
  };

  // ---------- Configurações › Gemini ----------
  let models = null;

  G.render = () => {
    const box = $('geminiBox');
    if (!box) return;
    const c = G.config(), s = G.stats();
    box.innerHTML = `<section>
      <div class="field"><label for="gToken">Token (API key) do Gemini</label>
        <input id="gToken" type="password" autocomplete="off" spellcheck="false" placeholder="${c.token ? '•••••••• (guardado neste navegador)' : 'AIza…'}"></div>
      <p class="hint">Cria-o no Google AI Studio (<i>Get API key</i>). Fica guardado <b>só neste navegador</b>, não vai para a base.
        O admin aberto noutro navegador, ou noutro endereço (ex.: o do vaio e o ficheiro local), pede-o de novo.</p>
      <div class="row">
        <button id="gSave">${c.token ? 'Trocar token' : 'Guardar token'}</button>
        ${c.token ? '<button id="gTest" class="secondary">Testar e carregar modelos</button><button id="gRemove" class="ghost">Remover token</button>' : ''}
      </div>
      <div id="gMsg"></div>
    </section>
    <section>
      <h3 style="margin-top:0">Modelos e limites</h3>
      <div class="grid">
        <div class="field"><label for="gModel">Modelo</label>
          ${models ? `<select id="gModel">${models.map((m) => `<option value="${esc(m.id)}" ${m.id === c.model ? 'selected' : ''}>${esc(m.label)} (${esc(m.id)})</option>`).join('')}
            ${models.some((m) => m.id === c.model) ? '' : `<option value="${esc(c.model)}" selected>${esc(c.model)}</option>`}</select>`
            : `<input id="gModel" value="${esc(c.model)}" spellcheck="false">`}</div>
        <div class="field"><label for="gImageModel">Modelo de imagens</label>
          ${models ? `<select id="gImageModel">${models.map((m) => `<option value="${esc(m.id)}" ${m.id === c.imageModel ? 'selected' : ''}>${esc(m.label)} (${esc(m.id)})</option>`).join('')}
            ${models.some((m) => m.id === c.imageModel) ? '' : `<option value="${esc(c.imageModel)}" selected>${esc(c.imageModel)}</option>`}</select>`
            : `<input id="gImageModel" value="${esc(c.imageModel)}" spellcheck="false">`}</div>
        <div class="field"><label for="gRpm">Pedidos por minuto (RPM)</label><input id="gRpm" type="number" min="0" value="${c.rpm}"></div>
        <div class="field"><label for="gRpd">Pedidos por dia (RPD)</label><input id="gRpd" type="number" min="0" value="${c.rpd}"></div>
      </div>
      <p class="hint">Põe os limites do teu plano (Google AI Studio › <i>Rate limits</i>). A API não diz quanto falta da quota:
        a barra no topo mostra os pedidos feitos <b>por este admin neste navegador</b> contra estes limites, e o admin espera
        quando chega ao limite por minuto. 0 = sem limite. O dia recomeça à meia-noite do Pacífico (8h em Lisboa).</p>
      <div class="row"><button id="gSaveCfg" class="secondary">Guardar modelo e limites</button></div>
      <p class="hint mt" style="margin-top:14px">Hoje: <b>${s.day}</b> pedido(s), ${fmtK(s.tokens)} tokens${s.errors ? `, ${s.errors} com erro` : ''}.</p>
    </section>`;
    $('gSave').onclick = () => {
      const v = $('gToken').value.trim();
      if (!v) { $('gMsg').innerHTML = A.msg('err', 'Cola o token.'); return; }
      G.saveConfig({ token: v }); models = null; G.render(); A.toast('ok', 'Token guardado neste navegador.');
    };
    if ($('gTest')) $('gTest').onclick = async () => {
      $('gMsg').innerHTML = A.msg('warn', 'A testar…');
      try { models = await G.listModels(); G.render(); $('gMsg').innerHTML = A.msg('ok', `Ligado ✓ ${models.length} modelo(s) disponíveis.`); }
      catch (e) { $('gMsg').innerHTML = A.msg('err', esc(e.message)); }
    };
    if ($('gRemove')) $('gRemove').onclick = () => {
      if (!confirm('Remover o token do Gemini deste navegador?')) return;
      G.saveConfig({ token: '' }); models = null; G.render();
    };
    $('gSaveCfg').onclick = () => {
      const model = $('gModel').value.trim();
      if (!model) { A.toast('warn', 'Indica o modelo.'); return; }
      const imageModel = $('gImageModel').value.trim() || DEFAULTS.imageModel;
      G.saveConfig({ model, imageModel, rpm: Math.max(0, Number($('gRpm').value) || 0), rpd: Math.max(0, Number($('gRpd').value) || 0) });
      G.render(); A.toast('ok', 'Configuração do Gemini guardada.');
    };
  };

  G.init = () => {
    document.addEventListener('click', (ev) => {
      const el = ev.target.closest('[data-tab-link]');
      if (el) A.app.showTab(el.dataset.tabLink);
    });
    G.renderBar();
    setInterval(G.renderBar, 5000); // atualiza o «por minuto»
  };
})();
