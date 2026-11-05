import { createCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const messages: Record<string, string> = {
  AUTH_REQUIRED: "Entra novamente na conta do adulto.",
  PARENT_LOCKED: "Desbloqueia a área dos pais para consultar as revisões.",
  FAMILY_NOT_FOUND: "Esta família não está disponível.",
  ATTEMPT_NOT_FOUND: "Esta ficha não está disponível nesta família.",
  ANSWER_NOT_FOUND: "Esta resposta não está disponível nesta família.",
  ATTEMPT_NOT_SUBMITTED: "A ficha ainda não foi entregue para revisão.",
  ANSWER_NOT_REVIEWABLE: "Só podes classificar respostas abertas preenchidas ou resolvidas no caderno.",
  REVIEW_REVISION_CONFLICT: "Esta classificação foi alterada noutro dispositivo. Atualiza a ficha antes de continuar.",
  OPERATION_REUSED: "Este pedido já foi usado com outros dados. Atualiza a ficha antes de continuar.",
  INVALID_REQUEST: "O pedido é inválido.",
  STORAGE_UNAVAILABLE: "Não foi possível confirmar o pedido de revisão. Tenta novamente.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  CORS_NOT_CONFIGURED: "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido.",
};
const hash = async (value: string) => Array.from(new Uint8Array(
  await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
), b => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID(), url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1(?=\/)/, "").replace(/^\/reviews(?=\/|$)/, "");
  const pending = /^\/v1\/families\/([^/]+)\/pending-reviews$/.exec(path);
  const completed = /^\/v1\/families\/([^/]+)\/reviewed-attempts$/.exec(path);
  const detail = /^\/v1\/attempts\/([^/]+)\/review$/.exec(path);
  const save = /^\/v1\/answers\/([^/]+)\/review$/.exec(path);
  const operation = pending ? "pending" : completed ? "completed" : detail ? "detail" : save ? "save" : "unknown";
  const corsPolicy = createCors(req, { methods: "GET, PUT, OPTIONS", parentUnlock: true });
  const cors = corsPolicy.headers;
  const reply = (status: number, data: unknown, code?: string) => {
    console.info(JSON.stringify({ requestId, domain: "reviews", operation, status, ...(code ? { code } : {}) }));
    return new Response(JSON.stringify(data), { status, headers: {
      ...cors, "Content-Type": "application/json", "Cache-Control": "no-store", "X-Request-Id": requestId,
    } });
  };
  const fail = (status: number, code: string) => reply(status, {
    error: { code, message: messages[code] ?? messages.INTERNAL_ERROR, requestId },
  }, code);
  if (!corsPolicy.configured) return fail(503, "CORS_NOT_CONFIGURED");
  if (!corsPolicy.allowed) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (corsPolicy.preflightResponse) return corsPolicy.preflightResponse;
  const targetId = pending?.[1] ?? completed?.[1] ?? detail?.[1] ?? save?.[1];
  if (!targetId) return fail(404, "ROUTE_NOT_FOUND");
  if (req.method !== (save ? "PUT" : "GET")) return fail(405, "METHOD_NOT_ALLOWED");
  const cursor = url.searchParams.get("cursor");
  if (!uuid.test(targetId) || (cursor !== null && (!(pending || completed) || !uuid.test(cursor)))) return fail(400, "INVALID_REQUEST");
  try {
    const projectUrl = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!projectUrl || !key) return fail(503, "STORAGE_UNAVAILABLE");
    const token = /^Bearer (\S+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
    if (!token || token.startsWith("chd_")) return fail(401, "AUTH_REQUIRED");
    const admin = createClient(projectUrl, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const { data: { user }, error: authError } = await admin.auth.getUser(token);
    if (authError || !user || !user.email_confirmed_at) return fail(401, "AUTH_REQUIRED");
    let sessionId: string | undefined;
    try {
      const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
      if (claims.sub === user.id && typeof claims.session_id === "string" && uuid.test(claims.session_id)) sessionId = claims.session_id;
    } catch { /* Only claims from the already validated JWT are used. */ }
    const unlock = req.headers.get("x-parent-unlock") ?? "";
    if (!sessionId || !/^par_[0-9a-f]{64}$/.test(unlock)) return fail(403, "PARENT_LOCKED");
    const params: Record<string, unknown> = {
      p_actor_id: user.id, p_auth_session_id: sessionId, p_unlock_hash: await hash(unlock),
    };
    let rpc: string;
    if (pending || completed) {
      rpc = pending ? "list_parent_pending_reviews" : "list_parent_completed_reviews";
      Object.assign(params, { p_family_id: targetId, p_cursor: cursor });
    } else if (detail) {
      rpc = "get_parent_attempt_review";
      params.p_attempt_id = targetId;
    } else {
      if (!req.headers.get("content-type")?.includes("application/json")) return fail(400, "INVALID_REQUEST");
      const reader = req.body?.getReader();
      if (!reader) return fail(400, "INVALID_REQUEST");
      const chunks: Uint8Array[] = []; let size = 0;
      while (true) {
        const { done, value } = await reader.read(); if (done) break;
        size += value.length;
        if (size > 4096) { await reader.cancel(); return fail(400, "INVALID_REQUEST"); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      let body;
      try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { return fail(400, "INVALID_REQUEST"); }
      if (!body || typeof body !== "object" || Array.isArray(body)
        || Object.keys(body).some(k => !["classification", "baseRevision", "operationId"].includes(k))
        || !["correct", "partially_correct", "incorrect"].includes(body.classification)
        || !Number.isInteger(body.baseRevision) || body.baseRevision < 0 || body.baseRevision >= 2147483647
        || typeof body.operationId !== "string" || !uuid.test(body.operationId)) return fail(400, "INVALID_REQUEST");
      rpc = "save_parent_answer_review";
      Object.assign(params, {
        p_answer_id: targetId, p_classification: body.classification, p_base_revision: body.baseRevision,
        p_operation_id: body.operationId,
        p_request_hash: await hash(JSON.stringify(["review_answer", user.id, targetId, body.classification, body.baseRevision])),
      });
    }
    const { data, error } = await admin.rpc(rpc, params);
    if (error || !data) return fail(503, "STORAGE_UNAVAILABLE");
    if (data.error) {
      const code = Object.hasOwn(messages, data.error) ? data.error : "STORAGE_UNAVAILABLE";
      const status = code === "PARENT_LOCKED" ? 403
        : ["FAMILY_NOT_FOUND", "ATTEMPT_NOT_FOUND", "ANSWER_NOT_FOUND"].includes(code) ? 404
        : ["REVIEW_REVISION_CONFLICT", "ATTEMPT_NOT_SUBMITTED", "OPERATION_REUSED"].includes(code) ? 409
        : code === "ANSWER_NOT_REVIEWABLE" ? 422 : code === "INVALID_REQUEST" ? 400 : 503;
      return fail(status, code);
    }
    return reply(200, data);
  } catch { return fail(500, "INTERNAL_ERROR"); }
});
