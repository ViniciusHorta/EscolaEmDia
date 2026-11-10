// Responsáveis: famílias, crianças, plano e assinaturas (forma de pagamento, pagamento, renovação),
// histórico de faturação por família e limites comerciais (Planos e limites). Requer 202611100001_admin_users.sql.
(() => {
  'use strict';
  const A = window.A, $ = A.$, esc = A.esc;
  const U = A.users = {};
  let users = [], settings = [], loadError = null;
  const events = new Map(); // familyId → eventos já carregados

  const channelLabel = { stripe: '💳 Cartão (Stripe)', google_play: '▶️ Google Play', app_store: '🍎 App Store', manual: '🛠️ Manual (admin)' };
  const statusLabel = {
    active: ['Ativa', 'ok'], in_grace: ['Em tolerância', 'warn'], pending: ['Pendente', 'warn'],
    expired: ['Expirada', 'grey'], canceled: ['Cancelada', 'grey'], revoked: ['Revogada', 'err'],
  };
  const planBadge = {
    premium: '<span class="badge premium">👑 Premium</span>',
    free: '<span class="badge grey">Free</span>',
    locked: '<span class="badge err">Bloqueada</span>',
  };
  const eventLabel = {
    'invoice.paid': 'Pagamento recebido (Stripe)', 'invoice.payment_failed': 'Pagamento falhou (Stripe)',
    'checkout.created': 'Checkout iniciado', 'checkout.session.completed': 'Checkout concluído', 'checkout.session.expired': 'Checkout expirado',
    'customer.subscription.created': 'Assinatura criada (Stripe)', 'customer.subscription.updated': 'Assinatura atualizada (Stripe)',
    'customer.subscription.deleted': 'Assinatura terminada (Stripe)',
    SUBSCRIPTION_PURCHASED: 'Compra (Google Play)', SUBSCRIPTION_RENEWED: 'Renovação (Google Play)',
    SUBSCRIPTION_RECOVERED: 'Pagamento recuperado (Google Play)', SUBSCRIPTION_RESTARTED: 'Reativada (Google Play)',
    SUBSCRIPTION_CANCELED: 'Cancelada pelo responsável (Google Play)', SUBSCRIPTION_IN_GRACE_PERIOD: 'Em tolerância (Google Play)',
    SUBSCRIPTION_ON_HOLD: 'Suspensa por falta de pagamento (Google Play)', SUBSCRIPTION_REVOKED: 'Revogada (Google Play)',
    SUBSCRIPTION_EXPIRED: 'Expirada (Google Play)', VOIDED_PURCHASE: 'Reembolso (Google Play)',
    'app.purchase': 'Compra confirmada pela app', 'subscription.granted': 'Premium manual concedido',
    'subscription.revoked': 'Premium manual retirado', 'subscription.superseded': 'Premium manual substituído por assinatura paga',
    'free_slot.claimed': 'Vaga gratuita atribuída', 'free_slot.released': 'Vaga gratuita libertada',
    'subscription.cancel_requested': 'Renovação cancelada pelo admin', 'subscription.cancelled_refunded': 'Cancelada e reembolsada pelo admin',
    'admin.period_end': 'Sincronizada após cancelamento (admin)', 'admin.immediate': 'Sincronizada após revogação (admin)',
  };

  const live = (s) => ['active', 'in_grace', 'pending'].includes(s.status);
  const cancellable = new Set(['stripe', 'google_play']); // App Store: Fase 6; manual: «Retirar manual»
  const settingHelp = {
    free_child_slots: 'Aumentar atribui logo vagas às crianças sem Premium. Reduzir não retira a vaga a quem já a tem.',
    max_premium_children: 'Não pode passar de 5: é o número de produtos-vaga criados nas lojas (premium_crianca_1…5).',
    free_max_questions: 'Fichas Free já publicadas acima do novo limite continuam válidas (aparecem como «Acima do limite Free»).',
    paid_grace_days: 'Aplica-se a partir da próxima atualização de cada assinatura.',
    stripe_renewal_leeway_hours: 'Aplica-se a partir da próxima atualização de cada assinatura.',
    store_renewal_leeway_hours: 'Aplica-se a partir da próxima atualização de cada assinatura.',
  };
  const money = (cents, cur) => cents == null ? '—'
    : (cents / 100).toLocaleString('pt-PT', { style: 'currency', currency: cur || 'EUR' });
  const day = (iso) => iso ? new Date(iso).toLocaleDateString('pt-PT') : '—';
  const children = (u) => u.families.flatMap((f) => f.children);
  const currentSub = (c) => c.subscriptions.find(live) || null;

  U.load = async () => {
    try {
      [users, settings] = await Promise.all([A.rpc('admin_list_users'), A.rpc('admin_list_billing_settings')]);
      users = users || []; settings = settings || []; loadError = null;
    } catch (e) {
      users = []; settings = [];
      loadError = e.code === 'MIGRATION_MISSING'
        ? 'As funções desta secção não existem nesta base. Aplica a migração <code>202611100001_admin_users.sql</code>.'
        : esc(e.message);
    }
    events.clear();
    $('userCount').hidden = !users.length;
    $('userCount').textContent = users.length;
  };

  // ---------- Indicadores ----------
  function stats() {
    const kids = users.flatMap(children);
    const subs = kids.map(currentSub).filter(Boolean);
    const paid = subs.filter((s) => s.channel !== 'manual');
    const monthly = paid.filter((s) => s.autoRenew).reduce((n, s) => n + (s.priceCents || 0), 0);
    const by = (ch) => subs.filter((s) => s.channel === ch).length;
    const card = (n, label) => `<div class="stat"><b>${n}</b><span>${label}</span></div>`;
    return `<div class="stats">
      ${card(users.length, 'Responsáveis')}
      ${card(kids.length, 'Crianças')}
      ${card(kids.filter((c) => c.plan === 'premium').length, '👑 Crianças Premium')}
      ${card(kids.filter((c) => c.plan === 'free').length, 'Crianças Free')}
      ${card(kids.filter((c) => c.plan === 'locked').length, 'Crianças bloqueadas')}
      ${card(`${by('stripe')} / ${by('google_play')} / ${by('app_store')} / ${by('manual')}`, 'Stripe / Play / Apple / Manual')}
      ${card(paid.filter((s) => !s.autoRenew).length, 'Assinaturas a terminar')}
      ${card(money(monthly, 'EUR'), 'Receita mensal recorrente (bruta)')}
    </div>`;
  }

  // ---------- Filtros ----------
  function matches(u) {
    const q = A.norm($('uSearch').value), plan = $('uPlan').value, ch = $('uChannel').value;
    const kids = children(u);
    if (q && !A.norm(u.email).includes(q) && !kids.some((c) => A.norm(c.name).includes(q))) return false;
    if (plan === 'nochild' && kids.length) return false;
    if (plan && plan !== 'nochild' && !kids.some((c) => c.plan === plan)) return false;
    if (ch) {
      const subs = kids.map(currentSub).filter(Boolean);
      if (ch === 'ending') return subs.some((s) => s.channel !== 'manual' && !s.autoRenew);
      if (ch === 'grace') return subs.some((s) => s.status === 'in_grace');
      return subs.some((s) => s.channel === ch);
    }
    return true;
  }

  // ---------- Render ----------
  function renewal(s) {
    if (!s) return '—';
    if (s.status === 'in_grace') return `Tolerância até ${A.fmtDate(s.graceUntil)}`;
    if (s.channel === 'manual') return `Termina ${A.fmtDate(s.currentPeriodEnd)}`;
    return s.autoRenew ? `Renova ${A.fmtDate(s.currentPeriodEnd)}`
      : `<span class="badge warn">Sem renovação</span><div class="sub">Termina ${A.fmtDate(s.currentPeriodEnd)}</div>`;
  }

  function childRow(c) {
    const s = currentSub(c);
    const past = c.subscriptions.filter((x) => x !== s);
    const [stLabel, stKind] = s ? (statusLabel[s.status] || [s.status, 'grey']) : [];
    const manualLive = c.subscriptions.some((x) => x.channel === 'manual' && live(x));
    return `<tr>
      <td><b>${esc(c.name)}</b><div class="sub">${c.schoolYear}.º Ano • desde ${day(c.createdAt)}</div></td>
      <td>${planBadge[c.plan] || esc(c.plan)}${c.freeSlotSince ? `<div class="sub">vaga gratuita desde ${day(c.freeSlotSince)}</div>` : ''}</td>
      <td>${s ? `${channelLabel[s.channel] || esc(s.channel)}${s.productId ? `<div class="sub"><code>${esc(s.productId)}</code></div>` : ''}` : '—'}</td>
      <td>${s ? `<span class="badge ${stKind}">${stLabel}</span>` : '—'}</td>
      <td>${s ? `${A.fmtDate(s.lastPaymentAt || s.currentPeriodStart)}<div class="sub">início ${day(s.createdAt)}${s.payments ? ` • ${s.payments} pagamento(s)` : ''}</div>` : '—'}</td>
      <td>${renewal(s)}</td>
      <td>${s && s.channel !== 'manual' ? money(s.priceCents, s.currency) + '/mês' : '—'}</td>
      <td>${c.completedAttempts} fichas<div class="sub">último uso ${day(c.lastActivityAt)}</div></td>
      <td class="actions">${manualLive
        ? `<button class="sm danger" data-act="revoke" data-child="${c.childId}" data-name="${esc(c.name)}">Retirar manual</button>`
        : s && cancellable.has(s.channel)
          ? `<button class="sm danger" data-act="cancel" data-sub="${s.id}">Cancelar</button>`
          : c.plan !== 'premium' ? `<button class="sm secondary" data-act="grant" data-child="${c.childId}" data-name="${esc(c.name)}">👑 Conceder</button>` : ''}</td>
    </tr>${past.length ? `<tr><td colspan="9" class="sub">Assinaturas anteriores: ${past.map((x) =>
        `${channelLabel[x.channel] || esc(x.channel)} — ${(statusLabel[x.status] || [x.status])[0].toLowerCase()} (${day(x.createdAt)} → ${day(x.currentPeriodEnd)})`).join(' • ')}</td></tr>` : ''}`;
  }

  function familyBlock(f, many) {
    const head = many || f.status !== 'active' || f.stripeCustomerId || f.members > 1
      ? `<div class="row small muted" style="margin-top:10px">
          ${many ? `<b>Família criada a ${day(f.createdAt)}</b>` : ''}
          ${f.status !== 'active' ? `<span class="badge err">${esc(f.status)}${f.closedAt ? ' • ' + day(f.closedAt) : ''}</span>` : ''}
          ${f.role === 'member' ? '<span class="badge grey">Membro convidado</span>' : ''}
          ${f.members > 1 ? `<span>${f.members} responsáveis</span>` : ''}
          ${f.stripeCustomerId ? `<span>Cliente Stripe <code>${esc(f.stripeCustomerId)}</code></span>` : ''}
        </div>` : '';
    const table = f.children.length
      ? `<div style="overflow-x:auto"><table class="tbl"><thead><tr><th>Criança</th><th>Plano</th><th>Pagamento</th><th>Estado</th>
          <th>Último pagamento</th><th>Renovação</th><th>Valor</th><th>Atividade</th><th></th></tr></thead>
          <tbody>${f.children.map(childRow).join('')}</tbody></table></div>`
      : '<p class="hint" style="margin:8px 0 0">Família sem crianças.</p>';
    return `${head}${table}
      <details data-family="${f.familyId}"><summary>Histórico de pagamentos e eventos</summary><div class="events">A carregar…</div></details>`;
  }

  function userCard(u) {
    const kids = children(u);
    return `<div class="user">
      <div class="head">
        <span class="email">${esc(u.email || '(sem e-mail)')}</span>
        ${kids.some((c) => c.plan === 'premium') ? '<span class="badge premium">👑</span>' : ''}
        ${u.emailConfirmedAt ? '' : '<span class="badge warn">E-mail por confirmar</span>'}
        ${u.provider && u.provider !== 'email' ? `<span class="badge grey">${esc(u.provider)}</span>` : ''}
        <span class="spacer"></span>
        <button class="sm ghost" data-act="copy" data-text="${esc(u.email || '')}">Copiar e-mail</button>
      </div>
      <div class="meta">Conta criada ${A.fmtDate(u.createdAt)} • último acesso ${A.fmtDate(u.lastSignInAt)}
        • termos aceites ${A.fmtDate(u.lastLegalAcceptanceAt)} • <code>${esc(u.userId)}</code></div>
      ${u.families.length ? u.families.map((f) => familyBlock(f, u.families.length > 1)).join('')
        : '<p class="hint" style="margin:8px 0 0">Ainda não criou família.</p>'}
    </div>`;
  }

  U.render = () => {
    renderPlans();
    if (loadError) { $('uStats').innerHTML = ''; $('userList').innerHTML = A.msg('err', loadError); $('uCount').textContent = ''; return; }
    const list = users.filter(matches);
    $('uCount').textContent = list.length === users.length ? `${users.length}` : `${list.length} de ${users.length}`;
    $('uStats').innerHTML = stats();
    $('userList').innerHTML = list.length ? list.map(userCard).join('') : '<div class="empty">Nenhum responsável neste filtro.</div>';
  };

  // ---------- Histórico (carregado ao abrir) ----------
  function eventRow(e) {
    const r = e.payload && e.payload.result;
    const outcome = r && (r.error ? `<span class="badge err">${esc(r.error)}</span>` : r.ignored ? '<span class="badge grey">ignorado</span>' : '');
    return `<div class="event">
      <span>${A.fmtDate(e.createdAt)}</span>
      <span class="muted">${esc(e.source)}</span>
      <div><b>${esc(eventLabel[e.eventType] || e.eventType)}</b>${e.childName ? ` • ${esc(e.childName)}` : ''} ${outcome || ''}
        ${e.payload && Object.keys(e.payload).length ? `<details><summary class="small">detalhes</summary><pre>${esc(JSON.stringify(e.payload, null, 2))}</pre></details>` : ''}</div>
    </div>`;
  }

  async function loadEvents(details) {
    const id = details.dataset.family, box = details.querySelector('.events');
    try {
      if (!events.has(id)) events.set(id, (await A.rpc('admin_family_billing_events', { p_family_id: id, p_limit: 200 })) || []);
      const list = events.get(id);
      box.innerHTML = list.length ? list.map(eventRow).join('') : '<span class="muted small">Sem eventos.</span>';
    } catch (e) { box.innerHTML = A.msg('err', esc(e.message)); }
  }

  // ---------- Premium manual ----------
  async function grant(childId, name) {
    const ok = await A.dialog({
      title: `Conceder Premium a ${name}`,
      body: `<p class="hint">Premium manual, sem pagamento (testes ou casos excecionais). Fica registado no histórico.</p>
        <div class="field"><label for="gDays">Dias</label><input id="gDays" name="days" type="number" min="1" max="3650" value="30" required></div>
        <div class="field"><label for="gNote">Nota (motivo)</label><input id="gNote" name="note" maxlength="200"></div>`,
      ok: 'Conceder',
      onSubmit: (form) => A.rpc('admin_grant_premium', {
        p_child_id: childId, p_days: Number(form.days.value), p_note: form.note.value.trim() || null }),
    });
    if (ok) { A.toast('ok', `Premium concedido a ${esc(name)}.`); await U.load(); U.render(); }
  }

  async function revoke(childId, name) {
    const ok = await A.dialog({
      title: `Retirar Premium manual de ${name}`,
      body: `<p class="hint">Só retira a concessão manual. Assinaturas pagas (Stripe, Google Play, App Store) gerem-se na plataforma de origem.</p>
        <div class="field"><label for="rNote">Nota (motivo)</label><input id="rNote" name="note" maxlength="200"></div>`,
      ok: 'Retirar', danger: true,
      onSubmit: (form) => A.rpc('admin_revoke_premium', { p_child_id: childId, p_note: form.note.value.trim() || null }),
    });
    if (ok) { A.toast('ok', `Premium manual retirado de ${esc(name)}.`); await U.load(); U.render(); }
  }

  // ---------- Cancelar assinatura paga ----------
  const findSub = (id) => {
    for (const u of users) for (const f of u.families) for (const c of f.children) {
      const sub = c.subscriptions.find((x) => x.id === id);
      if (sub) return { sub, child: c, user: u };
    }
    return null;
  };

  async function cancel(id) {
    const found = findSub(id);
    if (!found) return;
    const { sub, child, user } = found;
    const where = sub.channel === 'stripe' ? 'no Stripe' : 'na Google Play';
    const ok = await A.dialog({
      title: `Cancelar assinatura de ${child.name}`,
      body: `<p class="hint">${channelLabel[sub.channel]} • ${esc(user.email)} • ${money(sub.priceCents, sub.currency)}/mês.
          O cancelamento é feito ${where}; o responsável recebe a confirmação da plataforma.</p>
        <div class="field">
          <label><input type="radio" name="mode" value="period_end" ${sub.autoRenew ? 'checked' : 'disabled'} style="width:auto">
            Cancelar a renovação — mantém o Premium até ${A.fmtDate(sub.currentPeriodEnd)}, sem reembolso${sub.autoRenew ? '' : ' (já não renova)'}</label>
          <label><input type="radio" name="mode" value="immediate" ${sub.autoRenew ? '' : 'checked'} style="width:auto">
            Cancelar já e reembolsar o último pagamento — a criança perde o Premium agora</label>
        </div>
        <div class="field"><label for="cNote">Motivo (fica no histórico)</label><input id="cNote" name="note" maxlength="200"></div>`,
      ok: 'Cancelar assinatura', cancel: 'Voltar', danger: true,
      onSubmit: async (form) => {
        const mode = form.mode.value;
        if (!mode) throw new Error('Escolhe uma opção.');
        if (mode === 'immediate' && !confirm(`Cancelar já a assinatura de ${child.name} e reembolsar o último pagamento?`)) throw new Error('Cancelado.');
        return A.fn(`admin-billing/subscriptions/${id}/cancel`, { mode, note: form.note.value.trim() || null });
      },
    });
    if (!ok) return;
    A.toast(ok.refundError ? 'warn' : 'ok', ok.refundError
      ? `Assinatura cancelada, mas o reembolso falhou: ${esc(ok.refundError)}. Reembolsa no painel do Stripe.`
      : ok.mode === 'period_end' ? `Renovação cancelada. ${esc(child.name)} mantém o Premium até ao fim do período.`
        : `Assinatura cancelada e reembolsada.`, 7000);
    // O Stripe confirma pelo webhook em poucos segundos; a Google Play já foi sincronizada.
    await new Promise((r) => setTimeout(r, sub.channel === 'stripe' ? 3000 : 300));
    await U.load(); U.render();
  }

  // ---------- Editar limite ----------
  async function editSetting(key) {
    const st = settings.find((x) => x.key === key);
    if (!st) return;
    const ok = await A.dialog({
      title: `Alterar ${key}`,
      body: `<p class="hint">${esc(st.description)}</p>
        <div class="field"><label for="sValue">Valor (${st.min} a ${st.max})</label>
          <input id="sValue" name="settingValue" type="number" min="${st.min}" max="${st.max}" step="1" value="${st.value}" required></div>
        ${settingHelp[key] ? A.msg('warn', esc(settingHelp[key])) : ''}
        <div class="field mt"><label for="sNote">Motivo (fica no histórico)</label><input id="sNote" name="note" maxlength="200"></div>`,
      ok: 'Guardar',
      onSubmit: (form) => A.rpc('admin_set_billing_setting', {
        p_key: key, p_value: Number(form.settingValue.value), p_note: form.note.value.trim() || null }),
    });
    if (!ok) return;
    A.toast('ok', ok.changed ? `${esc(key)} = ${ok.value}.` : 'Sem alterações.');
    await U.load(); U.render();
  }

  // ---------- Planos e limites ----------
  function renderPlans() {
    $('plansBox').innerHTML = loadError ? A.msg('err', loadError) : settings.length
      ? `<section><div style="overflow-x:auto"><table class="tbl"><thead><tr><th>Limite</th><th>Valor</th><th>Descrição</th><th>Margens</th><th>Atualizado</th><th></th></tr></thead>
          <tbody>${settings.map((s) => `<tr><td><code>${esc(s.key)}</code></td><td><b>${s.value}</b></td>
            <td>${esc(s.description)}</td><td class="small muted">${s.min ?? '?'}–${s.max ?? '?'}</td>
            <td class="small muted">${A.fmtDate(s.updatedAt)}</td>
            <td class="actions">${s.min != null ? `<button class="sm secondary" data-act="edit-setting" data-key="${esc(s.key)}">Editar</button>` : ''}</td></tr>`).join('')}</tbody></table></div></section>`
      : '<div class="empty">Sem limites configurados.</div>';
  }

  U.init = () => {
    ['uSearch', 'uPlan', 'uChannel'].forEach((id) => $(id).addEventListener('input', U.render));
    $('userList').addEventListener('toggle', (ev) => {
      if (ev.target.matches('details[data-family]') && ev.target.open) loadEvents(ev.target);
    }, true);
    $('userList').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      if (btn.dataset.act === 'copy') A.copy(btn.dataset.text, btn);
      if (btn.dataset.act === 'grant') grant(btn.dataset.child, btn.dataset.name);
      if (btn.dataset.act === 'revoke') revoke(btn.dataset.child, btn.dataset.name);
      if (btn.dataset.act === 'cancel') cancel(btn.dataset.sub);
    });
    $('plansBox').addEventListener('click', (ev) => {
      const btn = ev.target.closest('button[data-act=edit-setting]');
      if (btn) editSetting(btn.dataset.key);
    });
  };
})();
