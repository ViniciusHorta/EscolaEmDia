/* Escola em Dia — consentimento de cookies (RGPD / Lei 41/2004)
 *
 * - Necessários: sempre ativos (apenas guardam esta escolha no localStorage).
 * - Estatísticas: Google Analytics 4, só é carregado DEPOIS do consentimento.
 *   Para ativar, preenche GA_MEASUREMENT_ID (ex.: "G-XXXXXXXXXX").
 *   Sem ID, nada de terceiros é carregado, mesmo com consentimento.
 *
 * Integra o Google Consent Mode v2 (tudo "denied" por omissão).
 * A escolha expira ao fim de 6 meses e o banner volta a aparecer.
 */
(() => {
  const GA_MEASUREMENT_ID = 'G-REXHC03NGE';
  const KEY = 'ed-consent';
  const VERSION = 1;
  const MAX_AGE = 1000 * 60 * 60 * 24 * 182; // ~6 meses

  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
  gtag('consent', 'default', {
    analytics_storage: 'denied',
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied',
    functionality_storage: 'granted',
    security_storage: 'granted',
    wait_for_update: 500,
  });

  const read = () => {
    try {
      const v = JSON.parse(localStorage.getItem(KEY));
      if (v && v.v === VERSION && Date.now() - v.ts < MAX_AGE) return v;
    } catch (_) { /* storage indisponível */ }
    return null;
  };
  const write = (analytics) => {
    const v = { v: VERSION, ts: Date.now(), analytics: !!analytics };
    try { localStorage.setItem(KEY, JSON.stringify(v)); } catch (_) {}
    return v;
  };

  let gaLoaded = false;
  const loadAnalytics = () => {
    if (!GA_MEASUREMENT_ID || gaLoaded) return;
    gaLoaded = true;
    const s = document.createElement('script');
    s.async = true;
    s.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(GA_MEASUREMENT_ID)}`;
    document.head.appendChild(s);
    gtag('js', new Date());
    gtag('config', GA_MEASUREMENT_ID);
  };
  const clearAnalyticsCookies = () => {
    const host = location.hostname.replace(/^www\./, '');
    document.cookie.split(';').map((c) => c.split('=')[0].trim())
      .filter((n) => /^_ga/.test(n) || n === '_gid')
      .forEach((n) => {
        [`; domain=.${host}`, ''].forEach((d) => {
          document.cookie = `${n}=; Max-Age=0; path=/${d}`;
        });
      });
  };

  const apply = (c) => {
    gtag('consent', 'update', { analytics_storage: c.analytics ? 'granted' : 'denied' });
    if (c.analytics) loadAnalytics(); else clearAnalyticsCookies();
  };

  /* Evento utilitário para os CTAs (só chega ao GA se houver consentimento) */
  window.edTrack = (name, params) => { if (gaLoaded) gtag('event', name, params || {}); };

  const stored = read();
  if (stored) apply(stored);

  const build = () => {
    const el = document.createElement('section');
    el.className = 'cookie';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'false');
    el.setAttribute('aria-labelledby', 'cookie-title');
    el.innerHTML = `
      <h2 id="cookie-title"><span aria-hidden="true">🍪</span> Cookies, só com a tua autorização</h2>
      <p>Usamos o essencial para o site funcionar. Se aceitares, usamos também estatísticas anónimas para perceber o que melhorar. <a href="/cookies">Saber mais</a></p>
      <div class="cookie__prefs" id="cookie-prefs" hidden>
        <div class="cookie__opt">
          <div><strong>Necessários</strong><small>Guardam esta escolha. Sempre ativos.</small></div>
          <label class="switch"><input type="checkbox" checked disabled aria-label="Cookies necessários (sempre ativos)"><span></span></label>
        </div>
        <div class="cookie__opt">
          <div><strong>Estatísticas</strong><small>Visitas e cliques, de forma agregada. Nunca para publicidade.</small></div>
          <label class="switch"><input type="checkbox" id="cookie-analytics" aria-label="Cookies de estatísticas"><span></span></label>
        </div>
      </div>
      <div class="cookie__actions">
        <button type="button" class="btn btn--ghost" data-c="reject">Recusar</button>
        <button type="button" class="btn btn--primary" data-c="accept">Aceitar</button>
      </div>
      <div class="cookie__actions" style="margin-top:6px">
        <button type="button" class="cookie__link" data-c="customize">Personalizar</button>
      </div>`;
    document.body.appendChild(el);

    const prefs = el.querySelector('#cookie-prefs');
    const box = el.querySelector('#cookie-analytics');
    const custom = el.querySelector('[data-c="customize"]');
    let lastFocus = null;

    const close = () => {
      el.classList.remove('is-open');
      if (lastFocus && lastFocus.focus) lastFocus.focus();
    };
    const choose = (analytics) => { apply(write(analytics)); close(); };

    el.addEventListener('click', (e) => {
      const action = e.target.closest('[data-c]')?.dataset.c;
      if (action === 'accept') choose(true);
      if (action === 'reject') choose(false);
      if (action === 'save') choose(box.checked);
      if (action === 'customize') {
        prefs.hidden = false;
        custom.textContent = 'Guardar preferências';
        custom.dataset.c = 'save';
        box.focus();
      }
    });
    el.addEventListener('keydown', (e) => { if (e.key === 'Escape' && read()) close(); });

    return {
      open(withPrefs) {
        lastFocus = document.activeElement;
        const c = read();
        box.checked = !!(c && c.analytics);
        prefs.hidden = !withPrefs;
        custom.textContent = withPrefs ? 'Guardar preferências' : 'Personalizar';
        custom.dataset.c = withPrefs ? 'save' : 'customize';
        requestAnimationFrame(() => el.classList.add('is-open'));
        if (withPrefs) setTimeout(() => box.focus(), 50);
      },
    };
  };

  const init = () => {
    const banner = build();
    if (!stored) setTimeout(() => banner.open(false), 900);
    document.addEventListener('click', (e) => {
      if (e.target.closest('[data-cookie-settings]')) { e.preventDefault(); banner.open(true); }
      const cta = e.target.closest('[data-event]');
      if (cta) window.edTrack(cta.dataset.event, { location: cta.dataset.location || '' });
    });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
