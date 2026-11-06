import { createCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const messages: Record<string, string> = {
  AUTH_REQUIRED: "A tua sessão terminou. Entra novamente na conta.",
  EMAIL_NOT_CONFIRMED: "Confirma o teu e-mail antes de continuar.",
  DOCUMENT_NOT_FOUND: "Este documento não está disponível.",
  DOCUMENT_OUTDATED:
    "Foi publicada uma versão mais recente deste documento. Revê a nova versão antes de aceitar.",
  INVALID_REQUEST: "O pedido é inválido.",
  SERVICE_NOT_CONFIGURED:
    "Os documentos legais estão temporariamente indisponíveis.",
  STORAGE_UNAVAILABLE:
    "Não foi possível consultar os documentos legais. Tenta novamente.",
  CORS_NOT_CONFIGURED:
    "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  REQUEST_TOO_LARGE: "O pedido excede o tamanho permitido.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
};

// Rotas:
//   GET  /v1/documents          versões em vigor (público, usado no registo)
//   GET  /v1/documents/{id}     uma versão concreta (público; versões publicadas são públicas)
//   GET  /v1/acceptances        estado do responsável autenticado
//   POST /v1/acceptances        aceitar as versões em vigor { documentIds: [...] }
Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const corsPolicy = createCors(req, {
    methods: "GET, POST, OPTIONS",
    retryAfter: false,
  });
  const cors = corsPolicy.headers;
  const path = new URL(req.url).pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/legal(?=\/|$)/, "");
  const documentRoute = /^\/v1\/documents\/([^/]+)$/.exec(path);
  const operation =
    path === "/v1/documents"
      ? "documents"
      : documentRoute
        ? "document"
        : path === "/v1/acceptances"
          ? "acceptances"
          : "unknown";
  const reply = (status: number, data: unknown, code?: string) => {
    console.info(
      JSON.stringify({
        requestId,
        domain: "legal",
        operation,
        method: req.method,
        status,
        ...(code ? { code } : {}),
      }),
    );
    return new Response(JSON.stringify(data), {
      status,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "X-Request-Id": requestId,
      },
    });
  };
  const fail = (status: number, code: string) =>
    reply(
      status,
      {
        error: {
          code,
          message: messages[code] ?? messages.INTERNAL_ERROR,
          requestId,
        },
      },
      code,
    );

  if (!corsPolicy.configured) return fail(503, "CORS_NOT_CONFIGURED");
  if (!corsPolicy.allowed) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (corsPolicy.preflightResponse) return corsPolicy.preflightResponse;
  if (operation === "unknown") return fail(404, "ROUTE_NOT_FOUND");
  if (
    operation === "acceptances"
      ? req.method !== "GET" && req.method !== "POST"
      : req.method !== "GET"
  )
    return fail(405, "METHOD_NOT_ALLOWED");
  if (documentRoute && !uuid.test(documentRoute[1]))
    return fail(400, "INVALID_REQUEST");

  try {
    const projectUrl = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!projectUrl || !key) return fail(503, "SERVICE_NOT_CONFIGURED");
    const admin = createClient(projectUrl, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    if (operation === "documents") {
      const { data, error } = await admin.rpc("legal_current_documents");
      if (error) return fail(503, "STORAGE_UNAVAILABLE");
      return reply(200, { items: data ?? [] });
    }
    if (operation === "document") {
      const { data, error } = await admin.rpc("legal_document_by_id", {
        p_id: documentRoute![1],
      });
      if (error) return fail(503, "STORAGE_UNAVAILABLE");
      if (!data) return fail(404, "DOCUMENT_NOT_FOUND");
      return reply(200, data);
    }

    // Aceites: exigem sessão adulta válida e e-mail confirmado.
    const token = /^Bearer (\S+)$/i.exec(
      req.headers.get("authorization") ?? "",
    )?.[1];
    if (!token) return fail(401, "AUTH_REQUIRED");
    const {
      data: { user },
      error: authError,
    } = await admin.auth.getUser(token);
    if (authError || !user) return fail(401, "AUTH_REQUIRED");
    if (!user.email_confirmed_at) return fail(403, "EMAIL_NOT_CONFIRMED");

    if (req.method === "GET") {
      const { data, error } = await admin.rpc("legal_acceptance_status", {
        p_user_id: user.id,
      });
      if (error || !data) return fail(503, "STORAGE_UNAVAILABLE");
      return reply(200, data);
    }

    const length = Number(req.headers.get("content-length") ?? "0");
    if (length > 4096) return fail(413, "REQUEST_TOO_LARGE");
    let body: unknown;
    try {
      const text = await req.text();
      if (text.length > 4096) return fail(413, "REQUEST_TOO_LARGE");
      body = JSON.parse(text);
    } catch {
      return fail(400, "INVALID_REQUEST");
    }
    const ids = (body as { documentIds?: unknown })?.documentIds;
    if (
      !Array.isArray(ids) ||
      ids.length < 1 ||
      ids.length > 10 ||
      !ids.every((id) => typeof id === "string" && uuid.test(id))
    )
      return fail(400, "INVALID_REQUEST");

    // Prova do aceite: IP do cliente (primeiro salto) e agente, quando disponíveis.
    const forwarded = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
    const ip =
      forwarded && /^[0-9a-f.:]{3,45}$/i.test(forwarded) ? forwarded : null;
    const userAgent = req.headers.get("user-agent")?.slice(0, 512) ?? null;
    const { data, error } = await admin.rpc("accept_legal_documents", {
      p_user_id: user.id,
      p_document_ids: [...new Set(ids.map((id: string) => id.toLowerCase()))],
      p_ip: ip,
      p_user_agent: userAgent,
    });
    if (error) {
      const code = error.message;
      if (code === "DOCUMENT_OUTDATED") return fail(409, code);
      if (code === "AUTH_REQUIRED") return fail(401, code);
      if (code === "INVALID_REQUEST") return fail(400, code);
      return fail(503, "STORAGE_UNAVAILABLE");
    }
    return reply(200, data);
  } catch {
    return fail(500, "INTERNAL_ERROR");
  }
});
