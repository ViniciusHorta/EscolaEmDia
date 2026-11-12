// Pagamentos Web (Stripe) — apenas para o responsável com a área parental desbloqueada.
//   POST /v1/children/{childId}/checkout   {clientRequestId}  → {url, sessionId}
//   POST /v1/families/{familyId}/portal                        → {url}
//   POST /v1/children/{childId}/play/offer                     → {productId, obfuscatedAccountId}  (Android)
//   POST /v1/play/purchases   {productId, purchaseToken}      → {plan, childId}                    (Android)
//   POST /v1/children/{childId}/apple/offer                    → {productId, appAccountToken}       (iOS)
//   POST /v1/apple/transactions   {transactionId}               → {plan, childId}                    (iOS)
// Stripe: o Premium só é ativado pelo webhook (stripe-webhook).
// Google Play: a compra é verificada na API da Google aqui (logo após a compra) e também
// pelas notificações em tempo real (play-notifications); ambas aplicam o mesmo estado.
// App Store: igual, com a App Store Server API e as notificações app-store-notifications.
import { createCors } from "../_shared/cors.ts";
import { StripeError, stripeClient } from "../_shared/stripe.ts";
import { PlayError, playClient, readServiceAccount } from "../_shared/google_play.ts";
import { syncPlayPurchase } from "../_shared/play_sync.ts";
import { AppleError, appStoreClient, readAppleConfig } from "../_shared/app_store.ts";
import { syncAppleSubscription } from "../_shared/app_store_sync.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const encoder = new TextEncoder();
const hash = async (value: string) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");

const messages: Record<string, string> = {
  AUTH_REQUIRED: "A tua sessão terminou. Entra novamente na conta.",
  PARENT_LOCKED: "Desbloqueia a área do responsável para continuar.",
  EMAIL_NOT_CONFIRMED: "Confirma o teu e-mail antes de continuar.",
  CHILD_NOT_FOUND: "Este perfil não está disponível.",
  FAMILY_NOT_FOUND: "Esta família não está disponível.",
  CHILD_ALREADY_PREMIUM: "Esta criança já tem o Premium ativo.",
  MAX_PREMIUM_CHILDREN_REACHED: "A família já atingiu o número máximo de crianças Premium.",
  NO_STRIPE_CUSTOMER: "Ainda não existe nenhuma subscrição paga nesta família.",
  PURCHASE_NOT_VERIFIED: "Não foi possível confirmar a compra com a loja. Tenta novamente.",
  PURCHASE_NOT_LINKED: "Esta compra não pôde ser associada a uma criança. Pede o reembolso à Apple em reportaproblem.apple.com.",
  PURCHASE_REFUSED: "Esta compra não pôde ser associada a uma criança e foi reembolsada.",
  CHECKOUT_WEB_ONLY: "O pagamento com cartão está disponível na versão web.",
  PAYMENTS_UNAVAILABLE: "Os pagamentos estão temporariamente indisponíveis. Tenta novamente.",
  INVALID_REQUEST: "Verifica os dados do pedido.",
  STORAGE_UNAVAILABLE: "Não foi possível concluir o pedido. Tenta novamente.",
  CORS_NOT_CONFIGURED: "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
};
const statusFor: Record<string, number> = {
  CHILD_NOT_FOUND: 404,
  FAMILY_NOT_FOUND: 404,
  CHILD_ALREADY_PREMIUM: 409,
  MAX_PREMIUM_CHILDREN_REACHED: 409,
  NO_STRIPE_CUSTOMER: 404,
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const path = new URL(req.url).pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/billing(?=\/|$)/, "");
  const checkoutRoute = /^\/v1\/children\/([^/]+)\/checkout$/.exec(path);
  const portalRoute = /^\/v1\/families\/([^/]+)\/portal$/.exec(path);
  const playOfferRoute = /^\/v1\/children\/([^/]+)\/play\/offer$/.exec(path);
  const playPurchaseRoute = path === "/v1/play/purchases";
  const appleOfferRoute = /^\/v1\/children\/([^/]+)\/apple\/offer$/.exec(path);
  const appleTransactionRoute = path === "/v1/apple/transactions";
  const operation = checkoutRoute ? "checkout" : portalRoute ? "portal" : playOfferRoute ? "play-offer"
    : playPurchaseRoute ? "play-purchase" : appleOfferRoute ? "apple-offer"
    : appleTransactionRoute ? "apple-transaction" : "unknown";
  const corsPolicy = createCors(req, { methods: "POST, OPTIONS", parentUnlock: true, retryAfter: false });
  const reply = (status: number, body: unknown, code?: string) => {
    console.info(JSON.stringify({ requestId, domain: "billing", operation, status, ...(code ? { code } : {}) }));
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsPolicy.headers, "Content-Type": "application/json", "Cache-Control": "no-store", "X-Request-Id": requestId },
    });
  };
  const fail = (status: number, code: string) =>
    reply(status, { error: { code, message: messages[code] ?? messages.INTERNAL_ERROR, requestId } }, code);

  if (!corsPolicy.configured) return fail(503, "CORS_NOT_CONFIGURED");
  if (!corsPolicy.allowed) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (corsPolicy.preflightResponse) return corsPolicy.preflightResponse;
  if (operation === "unknown") return fail(404, "ROUTE_NOT_FOUND");
  if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED");
  const targetId = (checkoutRoute ?? portalRoute ?? playOfferRoute ?? appleOfferRoute)?.[1] ?? null;
  if (targetId !== null && !uuid.test(targetId)) return fail(400, "INVALID_REQUEST");
  const isPlay = Boolean(playOfferRoute || playPurchaseRoute);
  const isApple = Boolean(appleOfferRoute || appleTransactionRoute);
  // Stripe: os URLs de regresso apontam para a origem web que fez o pedido (validada pelo CORS).
  const origin = req.headers.get("origin");
  if (!isPlay && !isApple && !origin) return fail(400, "CHECKOUT_WEB_ONLY");

  try {
    const projectUrl = Deno.env.get("SUPABASE_URL"),
      serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
      stripeKey = Deno.env.get("STRIPE_SECRET_KEY"),
      priceId = Deno.env.get("STRIPE_PRICE_ID");
    if (!projectUrl || !serverKey) return fail(503, "STORAGE_UNAVAILABLE");
    if (!isPlay && !isApple && (!stripeKey || !priceId)) return fail(503, "PAYMENTS_UNAVAILABLE");
    const token = /^Bearer (\S+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
    if (!token || token.startsWith("chd_")) return fail(401, "AUTH_REQUIRED");
    const admin = createClient(projectUrl, serverKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    // --- Adulto autenticado + área parental desbloqueada (igual às restantes funções do responsável).
    const { data: { user }, error: userError } = await admin.auth.getUser(token);
    if (userError || !user) return fail(401, "AUTH_REQUIRED");
    if (!user.email_confirmed_at) return fail(403, "EMAIL_NOT_CONFIRMED");
    const unlock = req.headers.get("x-parent-unlock") ?? "";
    if (!/^par_[0-9a-f]{64}$/.test(unlock)) return fail(403, "PARENT_LOCKED");
    let authSessionId: string | undefined;
    try {
      const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
      if (claims.sub === user.id && typeof claims.session_id === "string" && uuid.test(claims.session_id))
        authSessionId = claims.session_id;
    } catch { /* inválido */ }
    if (!authSessionId) return fail(401, "AUTH_REQUIRED");
    const { data: authorization, error: authzError } = await admin.rpc("use_parent_unlock", {
      p_actor_id: user.id, p_auth_session_id: authSessionId, p_token_hash: await hash(unlock), p_touch: true, p_revoke: false,
    });
    if (authzError) return fail(503, "STORAGE_UNAVAILABLE");
    if (!authorization || authorization.error) return fail(403, "PARENT_LOCKED");

    if (isPlay) {
      const serviceAccount = readServiceAccount(), packageName = Deno.env.get("PLAY_PACKAGE_NAME");
      if (!serviceAccount || !packageName) return fail(503, "PAYMENTS_UNAVAILABLE");
      if (playOfferRoute) {
        const { data: offer, error } = await admin.rpc("billing_play_offer", { p_actor_id: user.id, p_child_id: targetId });
        if (error || !offer) return fail(503, "STORAGE_UNAVAILABLE");
        if (offer.error) return fail(statusFor[offer.error] ?? 400, offer.error);
        // obfuscatedAccountId = família: liga a compra à família nas notificações da Google.
        return reply(200, { productId: offer.productId, obfuscatedAccountId: offer.familyId });
      }
      let body: { productId?: unknown; purchaseToken?: unknown };
      try {
        const text = await req.text();
        if (text.length > 4096) return fail(400, "INVALID_REQUEST");
        body = JSON.parse(text);
      } catch {
        return fail(400, "INVALID_REQUEST");
      }
      if (typeof body?.purchaseToken !== "string" || body.purchaseToken.length < 10 || body.purchaseToken.length > 2048 ||
          typeof body.productId !== "string" || !/^premium_crianca_[1-9][0-9]*$/.test(body.productId))
        return fail(400, "INVALID_REQUEST");
      const play = playClient(serviceAccount, packageName);
      const rpc = async (fn: string, args: Record<string, unknown>) => {
        const { data, error } = await admin.rpc(fn, args);
        if (error) throw new Error(`${fn}: ${error.message}`);
        return data;
      };
      // A compra tem de pertencer a uma família deste adulto (obfuscatedAccountId).
      const remote = await play.subscription(body.purchaseToken);
      const familyId = remote.externalAccountIdentifiers?.obfuscatedExternalAccountId;
      if (!familyId || !uuid.test(familyId) || !(await rpc("billing_actor_in_family", { p_actor_id: user.id, p_family_id: familyId })))
        return fail(404, "FAMILY_NOT_FOUND");
      const result = await syncPlayPurchase(play, rpc, body.purchaseToken, { type: "app.purchase" });
      if (result?.error) return fail(result.error === "CHILD_ALREADY_PREMIUM" ? 409 : 422, result.revoked ? "PURCHASE_REFUSED" : result.error);
      return reply(200, { plan: result?.plan ?? null, childId: result?.childId ?? null });
    }

    if (isApple) {
      const cfg = readAppleConfig();
      if (!cfg) return fail(503, "PAYMENTS_UNAVAILABLE");
      if (appleOfferRoute) {
        const { data: offer, error } = await admin.rpc("billing_apple_offer", { p_actor_id: user.id, p_child_id: targetId });
        if (error || !offer) return fail(503, "STORAGE_UNAVAILABLE");
        if (offer.error) return fail(statusFor[offer.error] ?? 400, offer.error);
        // appAccountToken = família (UUID): liga a compra à família nas notificações da Apple.
        return reply(200, { productId: offer.productId, appAccountToken: offer.familyId });
      }
      let body: { transactionId?: unknown };
      try {
        const text = await req.text();
        if (text.length > 1024) return fail(400, "INVALID_REQUEST");
        body = JSON.parse(text);
      } catch {
        return fail(400, "INVALID_REQUEST");
      }
      if (typeof body?.transactionId !== "string" || !/^[0-9]{1,32}$/.test(body.transactionId)) return fail(400, "INVALID_REQUEST");
      const apple = appStoreClient(cfg);
      const rpc = async (fn: string, args: Record<string, unknown>) => {
        const { data, error } = await admin.rpc(fn, args);
        if (error) throw new Error(`${fn}: ${error.message}`);
        return data;
      };
      // A compra tem de ser desta app e pertencer a uma família deste adulto (appAccountToken).
      const tx = await apple.transaction(body.transactionId);
      const familyId = typeof tx?.appAccountToken === "string" ? tx.appAccountToken.toLowerCase() : null;
      if (!tx || tx.bundleId !== cfg.bundleId || !familyId || !uuid.test(familyId) ||
          !(await rpc("billing_actor_in_family", { p_actor_id: user.id, p_family_id: familyId })))
        return fail(404, "FAMILY_NOT_FOUND");
      const result = await syncAppleSubscription(apple, cfg, rpc, String(tx.originalTransactionId), { type: "app.purchase" });
      if (result?.error) return fail(result.error === "CHILD_ALREADY_PREMIUM" ? 409 : 422, "PURCHASE_NOT_LINKED");
      return reply(200, { plan: result?.plan ?? null, childId: result?.childId ?? null });
    }

    const stripe = stripeClient(stripeKey!);

    if (portalRoute) {
      const { data: ctx, error } = await admin.rpc("billing_portal_context", { p_actor_id: user.id, p_family_id: targetId });
      if (error || !ctx) return fail(503, "STORAGE_UNAVAILABLE");
      if (ctx.error) return fail(statusFor[ctx.error] ?? 400, ctx.error);
      const session = await stripe("billing_portal/sessions", {
        params: { customer: ctx.customerId, return_url: `${origin}/?billing=portal`, locale: "pt" },
      });
      return reply(200, { url: session.url });
    }

    // --- Checkout
    let body: { clientRequestId?: unknown };
    try {
      const text = await req.text();
      if (text.length > 512) return fail(400, "INVALID_REQUEST");
      body = JSON.parse(text);
    } catch {
      return fail(400, "INVALID_REQUEST");
    }
    if (typeof body?.clientRequestId !== "string" || !uuid.test(body.clientRequestId)) return fail(400, "INVALID_REQUEST");
    const childId = targetId!;
    const { data: ctx, error: ctxError } = await admin.rpc("billing_checkout_context", { p_actor_id: user.id, p_child_id: childId });
    if (ctxError || !ctx) return fail(503, "STORAGE_UNAVAILABLE");
    if (ctx.error) return fail(statusFor[ctx.error] ?? 400, ctx.error);
    const familyId: string = ctx.familyId;

    let customerId: string | null = ctx.customerId;
    if (!customerId) {
      const customer = await stripe("customers", {
        params: { email: user.email, "metadata[family_id]": familyId, "preferred_locales[0]": "pt" },
        idempotencyKey: `customer-${familyId}`,
      });
      const { data: saved, error } = await admin.rpc("billing_save_stripe_customer", { p_family_id: familyId, p_customer_id: customer.id });
      if (error || !saved) return fail(503, "STORAGE_UNAVAILABLE");
      customerId = saved;
    }

    // Um checkout aberto de cada vez por criança: evita pagar duas vezes em dois separadores.
    for (const sessionId of ctx.openSessions as string[]) {
      try {
        await stripe(`checkout/sessions/${sessionId}/expire`, { params: {} });
      } catch { /* já concluída/expirada: o webhook trata */ }
      await admin.rpc("billing_update_checkout", { p_session_id: sessionId, p_status: "expired", p_subscription_id: null });
    }

    const { data: child } = await admin.from("children").select("display_name").eq("id", childId).maybeSingle();
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    const session = await stripe("checkout/sessions", {
      params: {
        mode: "subscription",
        // A Escola em Dia é o vendedor (IVA e faturação próprios): sem Managed Payments do Stripe.
        "managed_payments[enabled]": false,
        customer: customerId!,
        client_reference_id: childId,
        "line_items[0][price]": priceId!,
        "line_items[0][quantity]": 1,
        "metadata[family_id]": familyId,
        "metadata[child_id]": childId,
        "subscription_data[metadata][family_id]": familyId,
        "subscription_data[metadata][child_id]": childId,
        "subscription_data[description]": child?.display_name ? `Escola em Dia Premium — ${child.display_name}` : undefined,
        "custom_text[submit][message]": child?.display_name ? `Premium para ${child.display_name}. Cancela quando quiseres.` : undefined,
        success_url: `${origin}/?billing=success&child=${childId}&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${origin}/?billing=cancel&child=${childId}`,
        locale: "pt",
        expires_at: expiresAt,
      },
      idempotencyKey: `checkout-${body.clientRequestId}`,
    });
    const { error: recordError } = await admin.rpc("billing_record_checkout", {
      p_session_id: session.id, p_family_id: familyId, p_child_id: childId, p_actor_id: user.id,
      p_expires_at: new Date(expiresAt * 1000).toISOString(),
    });
    if (recordError) return fail(503, "STORAGE_UNAVAILABLE");
    return reply(201, { url: session.url, sessionId: session.id });
  } catch (error) {
    if (error instanceof AppleError) {
      console.error(JSON.stringify({ requestId, domain: "billing", appleStatus: error.status, appleCode: error.code, message: error.message }));
      return fail(error.status === 404 ? 404 : 502, error.status === 404 ? "INVALID_REQUEST" : "PURCHASE_NOT_VERIFIED");
    }
    if (error instanceof PlayError) {
      console.error(JSON.stringify({ requestId, domain: "billing", playStatus: error.status, message: error.message }));
      return fail(502, "PURCHASE_NOT_VERIFIED");
    }
    if (error instanceof StripeError) {
      console.error(JSON.stringify({ requestId, domain: "billing", stripeStatus: error.status, stripeCode: error.code, message: error.message }));
      return fail(502, "PAYMENTS_UNAVAILABLE");
    }
    return fail(500, "INTERNAL_ERROR");
  }
});
