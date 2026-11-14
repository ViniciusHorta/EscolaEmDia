// Sincroniza uma assinatura App Store com o banco: lê o estado atual na App Store Server API e aplica-o.
// Usado pela app logo após a compra (billing) e pelas notificações (app-store-notifications).
// A Apple não permite cancelar nem reembolsar pelo servidor: compras recusadas ficam registadas no histórico.
import { appStoreClient, AppleConfig, normalizeAppleSubscription } from "./app_store.ts";

type Apple = ReturnType<typeof appStoreClient>;
type Rpc = (fn: string, args: Record<string, unknown>) => Promise<any>;

export async function syncAppleSubscription(
  apple: Apple, cfg: AppleConfig, rpc: Rpc, originalTransactionId: string, event: { id?: string; type: string },
) {
  const sub = normalizeAppleSubscription(originalTransactionId, await apple.statuses(originalTransactionId));
  if (!sub) return { ignored: "not_found" };
  if (sub.bundleId && sub.bundleId !== cfg.bundleId) return { ignored: "bundle" };
  if (!sub.familyId) {
    // Compra que não passou pelo fluxo da app (sem appAccountToken): só auditoria.
    return { ignored: "missing_account_token", productId: sub.productId };
  }
  return await rpc("billing_apply_app_store_subscription", {
    p: { ...sub, eventId: event.id ?? null, eventType: event.type },
  });
}
