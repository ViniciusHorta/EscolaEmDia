// Acesso à Google Play Developer API com uma conta de serviço (sem SDK).
// Segredo: GOOGLE_PLAY_SERVICE_ACCOUNT = JSON da chave da conta de serviço, em base64.
export class PlayError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

type ServiceAccount = { client_email: string; private_key: string; token_uri?: string };

const b64url = (data: Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

let cached: { token: string; expires: number } | null = null;

export function readServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    const json = raw.trim().startsWith("{") ? raw : atob(raw.trim());
    const sa = JSON.parse(json);
    return sa.client_email && sa.private_key ? sa : null;
  } catch {
    return null;
  }
}

async function accessToken(sa: ServiceAccount) {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)));
  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) throw new PlayError(res.status, `oauth: ${body.error ?? res.status}`);
  cached = { token: body.access_token, expires: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cached.token;
}

export function playClient(sa: ServiceAccount, packageName: string) {
  const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}`;
  const call = async (path: string, method: "GET" | "POST" = "GET", body?: unknown) => {
    const res = await fetch(`${base}/${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${await accessToken(sa)}`,
        ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    const data = text ? JSON.parse(text) : {};
    if (!res.ok) throw new PlayError(res.status, data?.error?.message ?? `play ${res.status}`);
    return data;
  };
  return {
    /** Estado atual da assinatura (purchases.subscriptionsv2.get). */
    subscription: (token: string) => call(`purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`),
    /** Confirma a compra (sem isto a Google reembolsa ao fim de 3 dias). */
    acknowledge: (productId: string, token: string) =>
      call(`purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:acknowledge`, "POST", {}),
    /** Cancela a renovação: o acesso mantém-se até ao fim do período pago. */
    cancel: (productId: string, token: string) =>
      call(`purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:cancel`, "POST"),
    /** Cancela já e reembolsa (compra que não pode ser honrada). */
    revoke: (productId: string, token: string) =>
      call(`purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:revoke`, "POST"),
  };
}

/** Converte a resposta de subscriptionsv2.get no formato de billing_apply_play_subscription. */
export function normalizePlaySubscription(token: string, sub: any) {
  const item = sub.lineItems?.[0] ?? {};
  return {
    purchaseToken: token,
    linkedPurchaseToken: sub.linkedPurchaseToken ?? null,
    productId: item.productId ?? null,
    familyId: sub.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    state: sub.subscriptionState ?? null,
    startTime: sub.startTime ?? null,
    expiryTime: item.expiryTime ?? null,
    autoRenewing: Boolean(item.autoRenewingPlan?.autoRenewEnabled),
    priceMicros: item.autoRenewingPlan?.recurringPrice?.units != null
      ? Number(item.autoRenewingPlan.recurringPrice.units) * 1_000_000 + Number(item.autoRenewingPlan.recurringPrice.nanos ?? 0) / 1000
      : null,
    currency: item.autoRenewingPlan?.recurringPrice?.currencyCode ?? null,
    acknowledged: sub.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  };
}
