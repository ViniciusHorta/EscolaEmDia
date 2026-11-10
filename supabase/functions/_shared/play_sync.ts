// Sincroniza uma compra Google Play com o banco: lê o estado atual na API da Google, aplica-o,
// confirma (acknowledge) compras concedidas e revoga (com reembolso) as que não podem ser honradas.
// Usado pela app logo após a compra (billing) e pelas notificações em tempo real (play-notifications).
import { normalizePlaySubscription, playClient } from "./google_play.ts";

type Play = ReturnType<typeof playClient>;
type Rpc = (fn: string, args: Record<string, unknown>) => Promise<any>;

const refusals = new Set(["CHILD_ALREADY_PREMIUM", "MAX_PREMIUM_CHILDREN_REACHED", "NO_PURCHASE_INTENT"]);
const live = new Set(["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED"]);

export async function syncPlayPurchase(play: Play, rpc: Rpc, token: string, event: { id?: string; type: string }) {
  const raw = await play.subscription(token);
  const sub = normalizePlaySubscription(token, raw);
  if (!sub.familyId) {
    // Compra que não passou pelo fluxo da app (sem obfuscatedAccountId): só auditoria.
    return { ignored: "missing_account_id", productId: sub.productId };
  }
  const result = await rpc("billing_apply_play_subscription", {
    p: { ...sub, eventId: event.id ?? null, eventType: event.type },
  });
  if (sub.productId && result?.ok && result.acknowledge && !sub.acknowledged) {
    try {
      await play.acknowledge(sub.productId, token);
    } catch (error) {
      // A app e a notificação da Google chegam quase em simultâneo e ambas confirmam: a segunda
      // falha porque a compra já está confirmada. Só é erro se continuar por confirmar.
      const fresh = normalizePlaySubscription(token, await play.subscription(token));
      if (!fresh.acknowledged) throw error;
    }
  }
  if (sub.productId && result?.error && refusals.has(result.error) && live.has(sub.state ?? "")) {
    await play.revoke(sub.productId, token);
    return { ...result, revoked: true };
  }
  return result;
}
