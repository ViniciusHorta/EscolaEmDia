// Notificações em tempo real do Google Play (RTDN), entregues por uma subscrição push do Pub/Sub.
// Autenticação: segredo partilhado no URL (?token=PLAY_PUSH_TOKEN). Mesmo que alguém o descobrisse,
// só poderia pedir uma ressincronização: o estado é SEMPRE lido na API da Google, nunca do pedido.
// Respostas 2xx confirmam a mensagem; 5xx fazem o Pub/Sub repetir o envio.
import { createClient } from "npm:@supabase/supabase-js@2";
import { PlayError, playClient, readServiceAccount } from "../_shared/google_play.ts";
import { syncPlayPurchase } from "../_shared/play_sync.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// https://developer.android.com/google/play/billing/rtdn-reference#sub
const subscriptionTypes: Record<number, string> = {
  1: "SUBSCRIPTION_RECOVERED", 2: "SUBSCRIPTION_RENEWED", 3: "SUBSCRIPTION_CANCELED", 4: "SUBSCRIPTION_PURCHASED",
  5: "SUBSCRIPTION_ON_HOLD", 6: "SUBSCRIPTION_IN_GRACE_PERIOD", 7: "SUBSCRIPTION_RESTARTED",
  8: "SUBSCRIPTION_PRICE_CHANGE_CONFIRMED", 9: "SUBSCRIPTION_DEFERRED", 10: "SUBSCRIPTION_PAUSED",
  11: "SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED", 12: "SUBSCRIPTION_REVOKED", 13: "SUBSCRIPTION_EXPIRED",
  19: "SUBSCRIPTION_PRICE_CHANGE_UPDATED", 20: "SUBSCRIPTION_PENDING_PURCHASE_CANCELED",
};

function sameSecret(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  const projectUrl = Deno.env.get("SUPABASE_URL"), serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const pushToken = Deno.env.get("PLAY_PUSH_TOKEN"), packageName = Deno.env.get("PLAY_PACKAGE_NAME");
  const serviceAccount = readServiceAccount();
  if (!projectUrl || !serverKey || !pushToken || pushToken.length < 32 || !packageName || !serviceAccount)
    return json(503, { error: "NOT_CONFIGURED" });
  if (!sameSecret(new URL(req.url).searchParams.get("token") ?? "", pushToken)) return json(401, { error: "UNAUTHORIZED" });

  let envelope: any, notification: any;
  try {
    envelope = JSON.parse(await req.text());
    notification = JSON.parse(atob(envelope?.message?.data ?? ""));
  } catch {
    return json(200, { ignored: "malformed" }); // não adianta repetir uma mensagem inválida
  }
  const messageId: string | undefined = envelope?.message?.messageId ?? envelope?.message?.message_id;
  const log = (extra: Record<string, unknown>) =>
    console.info(JSON.stringify({ domain: "play-notifications", messageId, ...extra }));

  if (notification.packageName !== packageName) {
    log({ ignored: "package", packageName: notification.packageName });
    return json(200, { ignored: "package" });
  }
  if (notification.testNotification) {
    log({ test: true });
    return json(200, { test: true });
  }

  const admin = createClient(projectUrl, serverKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(`${fn}: ${error.message}`);
    return data;
  };

  try {
    if (messageId && (await rpc("billing_play_event_seen", { p_event_id: messageId }))) return json(200, { duplicate: true });
    const sn = notification.subscriptionNotification, voided = notification.voidedPurchaseNotification;
    const token: string | undefined = sn?.purchaseToken ?? voided?.purchaseToken;
    if (!token) {
      log({ ignored: "no_token" });
      return json(200, { ignored: "no_token" });
    }
    const type = sn ? subscriptionTypes[sn.notificationType] ?? `SUBSCRIPTION_${sn.notificationType}` : "VOIDED_PURCHASE";
    const play = playClient(serviceAccount, packageName);
    const result = await syncPlayPurchase(play, rpc, token, { id: messageId, type });
    log({ type, result });
    return json(200, { received: true });
  } catch (error) {
    log({ error: error instanceof PlayError ? `play ${error.status}: ${error.message}` : (error as Error).message });
    // 400/404/410 da Google: token inválido ou inexistente — repetir não ajuda.
    if (error instanceof PlayError && [400, 404, 410].includes(error.status)) return json(200, { ignored: "unknown_token" });
    return json(500, { error: "PROCESSING_FAILED" });
  }
});
