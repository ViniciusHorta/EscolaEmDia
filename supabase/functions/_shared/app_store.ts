// Acesso à App Store Server API com a chave de In-App Purchase (.p8), sem SDK.
// Segredos: APPLE_IAP_KEY (conteúdo do .p8, em texto ou base64), APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID,
//           APPLE_BUNDLE_ID. Opcional: APPLE_ENVIRONMENT=Sandbox para consultar primeiro o sandbox.
//
// As respostas da API trazem as transações assinadas (JWS). Como são obtidas diretamente da Apple por
// HTTPS e autenticadas com a nossa chave, lemos o conteúdo sem verificar a cadeia de certificados.
// As notificações (que chegam de fora) nunca são confiadas: servem só para saber o que voltar a consultar.
export class AppleError extends Error {
  constructor(public status: number, public code: number | undefined, message: string) {
    super(message);
  }
}

export type AppleConfig = { key: string; keyId: string; issuerId: string; bundleId: string; sandboxFirst: boolean };

const b64url = (data: Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export function readAppleConfig(): AppleConfig | null {
  const raw = Deno.env.get("APPLE_IAP_KEY"), keyId = Deno.env.get("APPLE_IAP_KEY_ID");
  const issuerId = Deno.env.get("APPLE_IAP_ISSUER_ID"), bundleId = Deno.env.get("APPLE_BUNDLE_ID");
  if (!raw || !keyId || !issuerId || !bundleId) return null;
  let key = raw.trim();
  try {
    if (!key.includes("BEGIN")) key = atob(key);
  } catch {
    return null;
  }
  if (!key.includes("PRIVATE KEY")) return null;
  return { key, keyId, issuerId, bundleId, sandboxFirst: Deno.env.get("APPLE_ENVIRONMENT") === "Sandbox" };
}

/** Lê o conteúdo de um JWS sem verificar a assinatura (ver nota no topo). */
export function decodeJws<T = any>(jws: string | undefined | null): T | null {
  if (!jws) return null;
  try {
    const part = jws.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = new TextDecoder().decode(Uint8Array.from(atob(part.padEnd(Math.ceil(part.length / 4) * 4, "=")), (c) => c.charCodeAt(0)));
    return JSON.parse(json) as T;
  } catch {
    return null;
  }
}

let cached: { token: string; expires: number; keyId: string } | null = null;

async function bearer(cfg: AppleConfig) {
  if (cached && cached.keyId === cfg.keyId && cached.expires > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId, typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: cfg.issuerId, iat: now, exp: now + 1800, aud: "appstoreconnect-v1", bid: cfg.bundleId }));
  const pem = cfg.key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  // WebCrypto devolve a assinatura ECDSA em formato r||s (64 bytes), o que o JWT ES256 exige.
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)));
  const token = `${header}.${claims}.${b64url(signature)}`;
  cached = { token, expires: Date.now() + 1800_000, keyId: cfg.keyId };
  return token;
}

const hosts = { Production: "https://api.storekit.itunes.apple.com", Sandbox: "https://api.storekit-sandbox.itunes.apple.com" };

export function appStoreClient(cfg: AppleConfig) {
  const order: (keyof typeof hosts)[] = cfg.sandboxFirst ? ["Sandbox", "Production"] : ["Production", "Sandbox"];
  // A Apple recomenda: tentar produção e, se a transação não existir (404), o sandbox (TestFlight e revisão).
  const get = async (path: string) => {
    let last: AppleError | null = null;
    for (const env of order) {
      const res = await fetch(`${hosts[env]}${path}`, { headers: { Authorization: `Bearer ${await bearer(cfg)}` } });
      const text = await res.text();
      const data = text ? JSON.parse(text) : {};
      if (res.ok) return { env, data };
      last = new AppleError(res.status, data?.errorCode, data?.errorMessage ?? `apple ${res.status}`);
      if (res.status !== 404) throw last;
    }
    throw last!;
  };
  return {
    /** Transação (Get Transaction Info). */
    transaction: async (transactionId: string) => {
      const { data } = await get(`/inApps/v1/transactions/${encodeURIComponent(transactionId)}`);
      return decodeJws(data.signedTransactionInfo);
    },
    /** Estado atual das assinaturas ligadas a uma transação (Get All Subscription Statuses). */
    statuses: async (transactionId: string) => (await get(`/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`)).data,
  };
}

const iso = (ms: unknown) => (typeof ms === "number" && ms > 0 ? new Date(ms).toISOString() : null);

/** Converte a resposta de Get All Subscription Statuses no formato de billing_apply_app_store_subscription. */
export function normalizeAppleSubscription(originalTransactionId: string, statuses: any) {
  for (const group of statuses?.data ?? []) {
    for (const item of group.lastTransactions ?? []) {
      if (String(item.originalTransactionId) !== originalTransactionId) continue;
      const tx = decodeJws(item.signedTransactionInfo) ?? {};
      const renewal = decodeJws(item.signedRenewalInfo) ?? {};
      return {
        originalTransactionId,
        transactionId: tx.transactionId ?? null,
        bundleId: tx.bundleId ?? statuses.bundleId ?? null,
        productId: tx.productId ?? null,
        familyId: tx.appAccountToken ?? null,
        status: item.status ?? null,
        purchaseDate: iso(tx.purchaseDate),
        expiresDate: iso(tx.expiresDate),
        gracePeriodExpiresDate: iso(renewal.gracePeriodExpiresDate),
        autoRenew: renewal.autoRenewStatus === 1,
        priceMilli: typeof tx.price === "number" ? tx.price : null,
        currency: tx.currency ?? null,
        environment: tx.environment ?? statuses.environment ?? null,
        revocationReason: tx.revocationReason ?? null,
      };
    }
  }
  return null;
}
