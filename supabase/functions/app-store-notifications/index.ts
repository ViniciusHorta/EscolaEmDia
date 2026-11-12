// App Store Server Notifications V2 (renovações, cancelamentos, reembolsos, falhas de cobrança…).
// Segurança: o conteúdo da notificação NUNCA é confiado — serve só para saber que assinatura mudou.
// O estado é sempre lido de novo na App Store Server API (com a nossa chave) e aplicado de forma idempotente.
// Respostas 200 confirmam a notificação; outras fazem a Apple repetir o envio (até ~3 dias).
import { createClient } from "npm:@supabase/supabase-js@2";
import { AppleError, appStoreClient, decodeJws, readAppleConfig } from "../_shared/app_store.ts";
import { syncAppleSubscription } from "../_shared/app_store_sync.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  const projectUrl = Deno.env.get("SUPABASE_URL"), serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cfg = readAppleConfig();
  if (!projectUrl || !serverKey || !cfg) return json(503, { error: "NOT_CONFIGURED" });

  let notification: any;
  try {
    const text = await req.text();
    if (text.length > 256 * 1024) return json(200, { ignored: "too_large" });
    notification = decodeJws(JSON.parse(text)?.signedPayload);
  } catch {
    notification = null;
  }
  if (!notification) return json(200, { ignored: "malformed" }); // repetir não ajuda

  const eventId: string | undefined = notification.notificationUUID;
  const type = [notification.notificationType, notification.subtype].filter(Boolean).join(".");
  const log = (extra: Record<string, unknown>) =>
    console.info(JSON.stringify({ domain: "app-store-notifications", eventId, type, ...extra }));

  if (notification.data?.bundleId && notification.data.bundleId !== cfg.bundleId) {
    log({ ignored: "bundle", bundleId: notification.data.bundleId });
    return json(200, { ignored: "bundle" });
  }
  if (notification.notificationType === "TEST") {
    log({ test: true, environment: notification.data?.environment });
    return json(200, { test: true });
  }
  const tx = decodeJws(notification.data?.signedTransactionInfo);
  const originalTransactionId = tx?.originalTransactionId ? String(tx.originalTransactionId) : null;
  if (!originalTransactionId) {
    log({ ignored: "no_transaction" });
    return json(200, { ignored: "no_transaction" });
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
    if (eventId && (await rpc("billing_apple_event_seen", { p_event_id: eventId }))) return json(200, { duplicate: true });
    const result = await syncAppleSubscription(appStoreClient(cfg), cfg, rpc, originalTransactionId, { id: eventId, type });
    log({ result });
    return json(200, { received: true });
  } catch (error) {
    log({ error: error instanceof AppleError ? `apple ${error.status} ${error.code}: ${error.message}` : (error as Error).message });
    // Transação inexistente (404) — repetir não ajuda.
    if (error instanceof AppleError && error.status === 404) return json(200, { ignored: "unknown_transaction" });
    return json(500, { error: "PROCESSING_FAILED" });
  }
});
