// Ações de administração sobre assinaturas pagas, chamadas pela ferramenta local tools/admin.
//   POST /admin-billing/subscriptions/{id}/cancel  {mode: "period_end" | "immediate", note?}
//     period_end → cancela a renovação; o acesso mantém-se até ao fim do período pago.
//     immediate  → cancela já e reembolsa o último pagamento.
// Autenticação: a chave service_role enviada pelo admin. É validada pela própria base: só ela pode executar
// admin_subscription_context. O estado final chega pelos webhooks (Stripe) e notificações (Google Play);
// no Google Play também sincronizamos logo, para o admin ver o resultado.
import { createClient } from "npm:@supabase/supabase-js@2";
import { refundLatestInvoice, StripeError, stripeClient } from "../_shared/stripe.ts";
import { PlayError, playClient, readServiceAccount } from "../_shared/google_play.ts";
import { syncPlayPurchase } from "../_shared/play_sync.ts";

// A ferramenta é aberta como ficheiro local (Origin "null"); a autorização é a chave no cabeçalho, não cookies.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  const projectUrl = Deno.env.get("SUPABASE_URL");
  if (!projectUrl) return json(503, { error: "NOT_CONFIGURED" });

  const route = /\/subscriptions\/([^/]+)\/cancel$/.exec(new URL(req.url).pathname);
  if (!route || !uuid.test(route[1])) return json(404, { error: "NOT_FOUND" });
  const subscriptionId = route[1];

  const key = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "") || (req.headers.get("apikey") ?? "");
  if (!key) return json(401, { error: "UNAUTHORIZED" });
  const db = createClient(projectUrl, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) throw Object.assign(new Error(`${fn}: ${error.message}`), { code: error.code });
    return data;
  };

  let body: { mode?: string; note?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "INVALID_REQUEST" });
  }
  const mode = body?.mode;
  if (mode !== "period_end" && mode !== "immediate") return json(400, { error: "INVALID_MODE" });
  const note = typeof body.note === "string" ? body.note.trim().slice(0, 200) || null : null;
  const log = (extra: Record<string, unknown>) =>
    console.info(JSON.stringify({ domain: "admin-billing", subscriptionId, mode, ...extra }));

  let sub: any;
  try {
    sub = await rpc("admin_subscription_context", { p_subscription_id: subscriptionId });
  } catch (error) {
    // Sem permissão para executar → a chave não é a service_role.
    log({ denied: (error as { code?: string }).code });
    return json(401, { error: "UNAUTHORIZED" });
  }
  if (sub?.error) return json(404, { error: sub.error });
  if (!["active", "in_grace", "pending"].includes(sub.status)) return json(409, { error: "SUBSCRIPTION_NOT_ACTIVE" });
  if (mode === "period_end" && !sub.autoRenew) return json(409, { error: "ALREADY_NOT_RENEWING" });

  try {
    const result: Record<string, unknown> = { channel: sub.channel, mode };
    if (sub.channel === "stripe") {
      const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
      if (!stripeKey) return json(503, { error: "PAYMENTS_UNAVAILABLE" });
      const stripe = stripeClient(stripeKey);
      if (mode === "period_end") {
        await stripe(`subscriptions/${sub.externalId}`, { params: { cancel_at_period_end: true } });
      } else {
        const current = await stripe(`subscriptions/${sub.externalId}`);
        await stripe(`subscriptions/${sub.externalId}`, { method: "DELETE" });
        try {
          result.refundId = await refundLatestInvoice(stripe, current.latest_invoice, "requested_by_customer");
        } catch (error) {
          // Já cancelada: o reembolso tem de ser feito à mão no painel do Stripe.
          result.refundError = (error as Error).message;
        }
      }
    } else if (sub.channel === "google_play") {
      const packageName = Deno.env.get("PLAY_PACKAGE_NAME"), serviceAccount = readServiceAccount();
      if (!packageName || !serviceAccount || !sub.productId) return json(503, { error: "PAYMENTS_UNAVAILABLE" });
      const play = playClient(serviceAccount, packageName);
      if (mode === "period_end") await play.cancel(sub.productId, sub.externalId);
      else await play.revoke(sub.productId, sub.externalId); // a Google reembolsa ao revogar
      result.sync = await syncPlayPurchase(play, rpc, sub.externalId, { type: `admin.${mode}` });
    } else {
      // manual → admin_revoke_premium; app_store → ainda sem integração (gerir na App Store Connect).
      return json(422, { error: "CHANNEL_NOT_SUPPORTED", channel: sub.channel });
    }
    await rpc("admin_log_subscription_action", {
      p_subscription_id: subscriptionId,
      p_action: mode === "period_end" ? "subscription.cancel_requested" : "subscription.cancelled_refunded",
      p_payload: { mode, note, refundId: result.refundId ?? null, refundError: result.refundError ?? null },
    });
    log({ ok: true });
    return json(200, { ok: true, ...result });
  } catch (error) {
    if (error instanceof StripeError) {
      log({ stripeStatus: error.status, stripeCode: error.code, message: error.message });
      return json(502, { error: "PROVIDER_ERROR", provider: "stripe", message: error.message });
    }
    if (error instanceof PlayError) {
      log({ playStatus: error.status, message: error.message });
      return json(502, { error: "PROVIDER_ERROR", provider: "google_play", message: error.message });
    }
    log({ error: (error as Error).message });
    return json(500, { error: "INTERNAL_ERROR" });
  }
});
