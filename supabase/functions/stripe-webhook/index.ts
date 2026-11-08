// Webhook do Stripe — única porta que ativa, renova ou termina o Premium pago na Web.
// Segurança: assinatura Stripe-Signature (STRIPE_WEBHOOK_SECRET); sem JWT (verify_jwt = false).
// Robustez: para cada evento lê o estado ATUAL da assinatura na API e aplica-o (idempotente e
// imune à ordem dos eventos). Erros devolvem 500 para o Stripe repetir o envio.
import { isoFromEpoch, StripeError, stripeClient, verifyStripeSignature } from "../_shared/stripe.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "METHOD_NOT_ALLOWED" });
  const projectUrl = Deno.env.get("SUPABASE_URL"),
    serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    stripeKey = Deno.env.get("STRIPE_SECRET_KEY"),
    webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!projectUrl || !serverKey || !stripeKey || !webhookSecret) return json(503, { error: "NOT_CONFIGURED" });

  const payload = await req.text();
  if (payload.length > 512 * 1024) return json(413, { error: "PAYLOAD_TOO_LARGE" });
  if (!(await verifyStripeSignature(payload, req.headers.get("stripe-signature"), webhookSecret))) {
    return json(400, { error: "INVALID_SIGNATURE" });
  }
  const event = JSON.parse(payload);
  const log = (extra: Record<string, unknown>) =>
    console.info(JSON.stringify({ domain: "stripe-webhook", eventId: event.id, type: event.type, ...extra }));

  const admin = createClient(projectUrl, serverKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const stripe = stripeClient(stripeKey);
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(`${fn}: ${error.message}`);
    return data;
  };

  // Estado atual da assinatura → banco. Devolve o resultado de billing_apply_stripe_subscription.
  const sync = async (subscriptionId: string) => {
    const sub = await stripe(`subscriptions/${subscriptionId}`);
    const item = sub.items?.data?.[0];
    const familyId = sub.metadata?.family_id, childId = sub.metadata?.child_id;
    if (!familyId) {
      // Assinatura que não foi criada pela app (ex.: outro produto na mesma conta): ignorar.
      await rpc("billing_record_stripe_event", {
        p_event_id: event.id, p_event_type: event.type, p_family_id: null, p_child_id: null,
        p_payload: { subscriptionId, ignored: "missing_metadata" },
      });
      return { ignored: true };
    }
    const result = await rpc("billing_apply_stripe_subscription", {
      p: {
        eventId: event.id,
        eventType: event.type,
        subscriptionId: sub.id,
        customerId: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
        familyId,
        childId: childId ?? null,
        status: sub.status,
        // Desde a API 2025-03-31 o período está nos itens da assinatura.
        periodStart: isoFromEpoch(sub.current_period_start ?? item?.current_period_start),
        periodEnd: isoFromEpoch(sub.current_period_end ?? item?.current_period_end),
        cancelAtPeriodEnd: Boolean(sub.cancel_at_period_end || sub.cancel_at),
        endedAt: isoFromEpoch(sub.ended_at),
        amount: item?.price?.unit_amount ?? null,
        currency: item?.price?.currency ?? null,
        priceId: item?.price?.id ?? null,
      },
    });
    // Compra que não pode ser honrada (criança já Premium, limite da família, cliente errado):
    // cancelar já e reembolsar, para o responsável não pagar sem acesso.
    if (result?.error && ["active", "trialing", "past_due"].includes(sub.status)) {
      await stripe(`subscriptions/${sub.id}`, { method: "DELETE" });
      await refundLatestInvoice(sub.latest_invoice);
      log({ subscriptionId: sub.id, cancelled: result.error });
    }
    return result;
  };

  const refundLatestInvoice = async (invoiceRef: unknown) => {
    const invoiceId = typeof invoiceRef === "string" ? invoiceRef : (invoiceRef as { id?: string })?.id;
    if (!invoiceId) return;
    try {
      const invoice = await stripe(`invoices/${invoiceId}`);
      let paymentIntent: string | undefined = invoice.payment_intent ?? undefined;
      if (!paymentIntent) {
        const payments = await stripe("invoice_payments", { method: "GET", params: { invoice: invoiceId } });
        const pi = payments?.data?.[0]?.payment?.payment_intent;
        paymentIntent = typeof pi === "string" ? pi : pi?.id;
      }
      if (paymentIntent && invoice.amount_paid > 0) {
        await stripe("refunds", { params: { payment_intent: paymentIntent, reason: "duplicate" }, idempotencyKey: `refund-${invoiceId}` });
      }
    } catch (error) {
      log({ refundFailed: invoiceId, message: (error as Error).message });
    }
  };

  try {
    if (await rpc("billing_stripe_event_seen", { p_event_id: event.id })) return json(200, { received: true, duplicate: true });
    const object = event.data?.object ?? {};
    let result: unknown = null;
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded":
        await rpc("billing_update_checkout", { p_session_id: object.id, p_status: "complete", p_subscription_id: object.subscription ?? null });
        if (object.subscription) result = await sync(object.subscription);
        break;
      case "checkout.session.expired":
        await rpc("billing_update_checkout", { p_session_id: object.id, p_status: "expired", p_subscription_id: null });
        await rpc("billing_record_stripe_event", {
          p_event_id: event.id, p_event_type: event.type, p_family_id: object.metadata?.family_id ?? null,
          p_child_id: object.metadata?.child_id ?? null, p_payload: { sessionId: object.id },
        });
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
      case "customer.subscription.paused":
      case "customer.subscription.resumed":
        result = await sync(object.id);
        break;
      case "invoice.paid":
      case "invoice.payment_failed": {
        const subscriptionId = object.subscription ?? object.parent?.subscription_details?.subscription;
        if (subscriptionId) result = await sync(typeof subscriptionId === "string" ? subscriptionId : subscriptionId.id);
        break;
      }
      default:
        log({ ignored: true });
    }
    log({ result });
    return json(200, { received: true });
  } catch (error) {
    log({ error: error instanceof StripeError ? `stripe ${error.status} ${error.code}` : (error as Error).message });
    return json(500, { error: "PROCESSING_FAILED" });
  }
});
