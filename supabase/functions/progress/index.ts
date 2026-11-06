import { createCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const messages: Record<string, string> = {
  AUTH_REQUIRED: "Entra novamente na conta do adulto.",
  PARENT_LOCKED: "Desbloqueia a área do responsável para consultar o acompanhamento.",
  CHILD_NOT_FOUND: "Este perfil não está disponível nesta família.",
  INVALID_REQUEST: "Os filtros ou a página do histórico são inválidos.",
  STORAGE_UNAVAILABLE:
    "Não foi possível carregar o acompanhamento. Tenta novamente.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  CORS_NOT_CONFIGURED:
    "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido.",
};
const hash = async (value: string) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID(),
    url = new URL(req.url);
  const path = url.pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/progress(?=\/|$)/, "");
  const route = /^\/v1\/children\/([^/]+)\/(progress|attempts)$/.exec(path);
  const operation = route?.[2] ?? "unknown";
  const policy = createCors(req, {
    methods: "GET, OPTIONS",
    parentUnlock: true,
  });
  const reply = (status: number, data: unknown, code?: string) => {
    console.info(
      JSON.stringify({
        requestId,
        domain: "progress",
        operation,
        status,
        ...(code ? { code } : {}),
      }),
    );
    return new Response(JSON.stringify(data), {
      status,
      headers: {
        ...policy.headers,
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
  if (!policy.configured) return fail(503, "CORS_NOT_CONFIGURED");
  if (!policy.allowed) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (policy.preflightResponse) return policy.preflightResponse;
  if (!route) return fail(404, "ROUTE_NOT_FOUND");
  if (req.method !== "GET") return fail(405, "METHOD_NOT_ALLOWED");
  const cursor = url.searchParams.get("cursor"),
    subjectId = url.searchParams.get("subjectId"),
    status = url.searchParams.get("status");
  if (
    !uuid.test(route[1]) ||
    (cursor !== null && !uuid.test(cursor)) ||
    (subjectId !== null && !uuid.test(subjectId)) ||
    (status !== null &&
      ![
        "in_progress",
        "submitted",
        "pending_review",
        "completed",
        "abandoned",
      ].includes(status)) ||
    [...url.searchParams.keys()].some(
      (k) => !["cursor", "subjectId", "status"].includes(k),
    ) ||
    (operation === "progress" && url.searchParams.size > 0)
  )
    return fail(400, "INVALID_REQUEST");
  try {
    const projectUrl = Deno.env.get("SUPABASE_URL"),
      key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!projectUrl || !key) return fail(503, "STORAGE_UNAVAILABLE");
    const token = /^Bearer (\S+)$/i.exec(
      req.headers.get("authorization") ?? "",
    )?.[1];
    if (!token || token.startsWith("chd_")) return fail(401, "AUTH_REQUIRED");
    const admin = createClient(projectUrl, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    const {
      data: { user },
      error: authError,
    } = await admin.auth.getUser(token);
    if (authError || !user || !user.email_confirmed_at)
      return fail(401, "AUTH_REQUIRED");
    let sessionId: string | undefined;
    try {
      const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const claims = JSON.parse(
        atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")),
      );
      if (
        claims.sub === user.id &&
        typeof claims.session_id === "string" &&
        uuid.test(claims.session_id)
      )
        sessionId = claims.session_id;
    } catch {
      /* Only claims from the already validated JWT are used. */
    }
    const unlock = req.headers.get("x-parent-unlock") ?? "";
    if (!sessionId || !/^par_[0-9a-f]{64}$/.test(unlock))
      return fail(403, "PARENT_LOCKED");
    const params: Record<string, unknown> = {
      p_actor_id: user.id,
      p_auth_session_id: sessionId,
      p_unlock_hash: await hash(unlock),
      p_child_id: route[1],
    };
    if (operation === "attempts")
      Object.assign(params, {
        p_cursor: cursor,
        p_subject_id: subjectId,
        p_status: status,
      });
    const { data, error } = await admin.rpc(
      operation === "progress"
        ? "get_parent_child_progress"
        : "list_parent_child_attempts",
      params,
    );
    if (error || !data) {
      if (error)
        console.warn(
          JSON.stringify({
            requestId,
            domain: "progress",
            operation,
            databaseCode: error.code,
          }),
        );
      return fail(503, "STORAGE_UNAVAILABLE");
    }
    if (data.error) {
      const code = Object.hasOwn(messages, data.error)
        ? data.error
        : "STORAGE_UNAVAILABLE";
      return fail(
        code === "PARENT_LOCKED"
          ? 403
          : code === "CHILD_NOT_FOUND"
            ? 404
            : code === "INVALID_REQUEST"
              ? 400
              : 503,
        code,
      );
    }
    return reply(200, data);
  } catch {
    return fail(500, "INTERNAL_ERROR");
  }
});
