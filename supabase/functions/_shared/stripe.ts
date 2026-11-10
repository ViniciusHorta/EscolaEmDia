// Cliente mínimo da API REST do Stripe (sem SDK) para as Edge Functions.
export class StripeError extends Error {
  constructor(public status: number, public code: string | undefined, message: string) {
    super(message);
  }
}

type Params = Record<string, string | number | boolean | undefined>;

export function stripeClient(secretKey: string) {
  return async function stripe(
    path: string,
    options: { method?: "GET" | "POST" | "DELETE"; params?: Params; idempotencyKey?: string } = {},
  ) {
    const method = options.method ?? (options.params ? "POST" : "GET");
    const form = new URLSearchParams();
    for (const [key, value] of Object.entries(options.params ?? {})) {
      if (value !== undefined) form.append(key, String(value));
    }
    const query = method === "POST" ? "" : form.size ? `?${form}` : "";
    const res = await fetch(`https://api.stripe.com/v1/${path}${query}`, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        ...(method === "POST" ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
        ...(options.idempotencyKey ? { "Idempotency-Key": options.idempotencyKey } : {}),
      },
      body: method === "POST" ? form : undefined,
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new StripeError(res.status, body?.error?.code, body?.error?.message ?? "Stripe error");
    }
    return body;
  };
}

type Stripe = ReturnType<typeof stripeClient>;

/** Reembolsa a última fatura paga de uma assinatura. Devolve o id do reembolso, ou null se não havia nada a reembolsar. */
export async function refundLatestInvoice(stripe: Stripe, invoiceRef: unknown, reason: "duplicate" | "requested_by_customer") {
  const invoiceId = typeof invoiceRef === "string" ? invoiceRef : (invoiceRef as { id?: string })?.id;
  if (!invoiceId) return null;
  const invoice = await stripe(`invoices/${invoiceId}`);
  let paymentIntent: string | undefined = invoice.payment_intent ?? undefined;
  if (!paymentIntent) {
    // Desde a API 2025-03-31 o pagamento está em invoice_payments.
    const payments = await stripe("invoice_payments", { method: "GET", params: { invoice: invoiceId } });
    const pi = payments?.data?.[0]?.payment?.payment_intent;
    paymentIntent = typeof pi === "string" ? pi : pi?.id;
  }
  if (!paymentIntent || !(invoice.amount_paid > 0)) return null;
  const refund = await stripe("refunds", { params: { payment_intent: paymentIntent, reason }, idempotencyKey: `refund-${invoiceId}` });
  return refund.id as string;
}

const encoder = new TextEncoder();

/** Verifica o cabeçalho Stripe-Signature (HMAC-SHA256 de `${t}.${payload}`), com tolerância de 5 min. */
export async function verifyStripeSignature(payload: string, header: string | null, secret: string, toleranceSeconds = 300) {
  if (!header) return false;
  const parts = header.split(",").map((p) => p.split("=", 2) as [string, string]);
  const t = Number(parts.find(([k]) => k === "t")?.[1]);
  const signatures = parts.filter(([k]) => k === "v1").map(([, v]) => v);
  if (!Number.isFinite(t) || !signatures.length) return false;
  if (Math.abs(Date.now() / 1000 - t) > toleranceSeconds) return false;
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${t}.${payload}`)));
  const expected = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  return signatures.some((sig) => timingSafeEqual(sig, expected));
}

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export const isoFromEpoch = (value: unknown) =>
  typeof value === "number" ? new Date(value * 1000).toISOString() : null;
