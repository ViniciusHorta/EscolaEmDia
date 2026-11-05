import { createCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const encoder = new TextEncoder();
const hex = (data: Uint8Array) =>
  Array.from(data, (b) => b.toString(16).padStart(2, "0")).join("");
const sha256 = async (text: string) =>
  hex(
    new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text))),
  );
const messages: Record<string, string> = {
  AUTH_REQUIRED: "Entra com a conta do adulto para autorizar este dispositivo.",
  EMAIL_NOT_CONFIRMED: "Confirma o e-mail da conta antes de continuar.",
  CHILD_NOT_FOUND: "Este perfil não está disponível nesta família.",
  INVALID_PIN: "O PIN não está correto. Tenta novamente.",
  PIN_LOCKED:
    "Demasiadas tentativas. Aguarda cinco minutos antes de tentar novamente.",
  PIN_BUSY: "Já existe uma tentativa em curso. Aguarda alguns instantes.",
  LOGIN_EXPIRED: "A tentativa expirou. Introduz o PIN novamente.",
  CHILD_SESSION_EXPIRED:
    "A tua sessão terminou. Escolhe o teu perfil e entra novamente.",
  INVALID_REQUEST: "O pedido é inválido.",
  SERVICE_NOT_CONFIGURED:
    "A entrada infantil está temporariamente indisponível.",
  STORAGE_UNAVAILABLE: "Não foi possível consultar a sessão. Tenta novamente.",
  CORS_NOT_CONFIGURED:
    "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
};
Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const corsPolicy = createCors(req, {
    methods: "GET, POST, OPTIONS",
    parentUnlock: false,
    retryAfter: true,
  });
  const cors = corsPolicy.headers;
  const path = new URL(req.url).pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/child-sessions(?=\/|$)/, "");
  const operation =
    path === "/v1/child-sessions"
      ? "login"
      : path === "/v1/child-sessions/me"
        ? "me"
        : path === "/v1/child-sessions/revoke"
          ? "revoke"
          : "unknown";
  const reply = (
    status: number,
    body: unknown,
    code?: string,
    retryAfter?: number,
  ) => {
    console.info(
      JSON.stringify({
        requestId,
        domain: "child-sessions",
        operation,
        status,
        ...(code ? { code } : {}),
      }),
    );
    return new Response(JSON.stringify(body), {
      status,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "X-Request-Id": requestId,
        ...(retryAfter ? { "Retry-After": String(retryAfter) } : {}),
      },
    });
  };
  const fail = (status: number, code: string, retryAfter?: number) =>
    reply(
      status,
      {
        error: {
          code,
          message: messages[code] ?? messages.INTERNAL_ERROR,
          requestId,
          ...(retryAfter ? { details: { retryAfter } } : {}),
        },
      },
      code,
      retryAfter,
    );
  const rpcFailure = (data: Record<string, unknown>) => {
    const code =
      typeof data.error === "string" ? data.error : "STORAGE_UNAVAILABLE";
    const status =
      code === "PIN_LOCKED"
        ? 429
        : code === "INVALID_PIN" || code === "CHILD_SESSION_EXPIRED"
          ? 401
          : code === "CHILD_NOT_FOUND"
            ? 404
            : code === "PIN_BUSY" || code === "LOGIN_EXPIRED"
              ? 409
              : 503;
    return fail(
      status,
      code,
      typeof data.retryAfter === "number" ? data.retryAfter : undefined,
    );
  };
  if (!corsPolicy.configured) return fail(503, "CORS_NOT_CONFIGURED");
  if (!corsPolicy.allowed) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (corsPolicy.preflightResponse) return corsPolicy.preflightResponse;
  if (operation === "unknown") return fail(404, "ROUTE_NOT_FOUND");
  if (req.method !== (operation === "me" ? "GET" : "POST"))
    return fail(405, "METHOD_NOT_ALLOWED");
  try {
    const url = Deno.env.get("SUPABASE_URL"),
      key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return fail(503, "SERVICE_NOT_CONFIGURED");
    const token = /^Bearer (\S+)$/i.exec(
      req.headers.get("authorization") ?? "",
    )?.[1];
    if (!token)
      return fail(
        401,
        operation === "login" ? "AUTH_REQUIRED" : "CHILD_SESSION_EXPIRED",
      );
    const admin = createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    if (operation !== "login") {
      // Child-only endpoints reject adult JWTs; sessions are opaque and revocable.
      if (!/^chd_[0-9a-f]{64}$/.test(token))
        return fail(401, "CHILD_SESSION_EXPIRED");
      const { data, error } = await admin.rpc("use_child_session", {
        p_token_hash: await sha256(token),
        p_revoke: operation === "revoke",
      });
      if (error || !data) return fail(503, "STORAGE_UNAVAILABLE");
      if (data.error) return rpcFailure(data);
      return reply(200, data);
    }
    const {
      data: { user },
      error: authError,
    } = await admin.auth.getUser(token);
    if (authError || !user) return fail(401, "AUTH_REQUIRED");
    if (!user.email_confirmed_at) return fail(403, "EMAIL_NOT_CONFIRMED");
    if (!req.headers.get("content-type")?.includes("application/json"))
      return fail(400, "INVALID_REQUEST");
    const reader = req.body?.getReader();
    if (!reader) return fail(400, "INVALID_REQUEST");
    let size = 0;
    const chunks: Uint8Array[] = [];
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1024) {
        await reader.cancel();
        return fail(400, "INVALID_REQUEST");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    let body;
    try {
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      return fail(400, "INVALID_REQUEST");
    }
    if (
      !body ||
      typeof body !== "object" ||
      Array.isArray(body) ||
      Object.keys(body).some((k) => k !== "childId" && k !== "pin") ||
      typeof body.childId !== "string" ||
      !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.childId) ||
      typeof body.pin !== "string" ||
      !/^[0-9]{4}$/.test(body.pin)
    )
      return fail(400, "INVALID_REQUEST");
    const pepper = Deno.env.get("CHILD_PIN_PEPPER");
    if (!pepper || pepper.length < 32)
      return fail(503, "SERVICE_NOT_CONFIGURED");
    const { data: challenge, error: startError } = await admin.rpc(
      "begin_child_pin_login",
      { p_actor_id: user.id, p_child_id: body.childId },
    );
    if (startError || !challenge) return fail(503, "STORAGE_UNAVAILABLE");
    if (challenge.error) return rpcFailure(challenge);
    if (
      challenge.algorithm !== "pbkdf2-sha256-hmac-pepper-v1" ||
      challenge.iterations !== 600000 ||
      !/^[0-9a-f]{32}$/.test(challenge.salt) ||
      !/^[0-9a-f]{64}$/.test(challenge.hash)
    )
      return fail(503, "STORAGE_UNAVAILABLE");
    const pepperKey = await crypto.subtle.importKey(
      "raw",
      encoder.encode(pepper),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const prehash = await crypto.subtle.sign(
      "HMAC",
      pepperKey,
      encoder.encode(
        `child-pin-v1:${challenge.familyId}:${body.childId}:${body.pin}`,
      ),
    );
    const material = await crypto.subtle.importKey(
      "raw",
      prehash,
      "PBKDF2",
      false,
      ["deriveBits"],
    );
    const salt = Uint8Array.from(challenge.salt.match(/../g)!, (v: string) =>
      parseInt(v, 16),
    );
    const bits = await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        salt,
        iterations: challenge.iterations,
      },
      material,
      256,
    );
    // Fixed-length comparison; do not return expected hashes or intermediate values.
    const candidate = hex(new Uint8Array(bits));
    let difference = 0;
    for (let i = 0; i < 64; i++)
      difference |= candidate.charCodeAt(i) ^ challenge.hash.charCodeAt(i);
    const accessToken = `chd_${hex(crypto.getRandomValues(new Uint8Array(32)))}`;
    const { data: session, error: finishError } = await admin.rpc(
      "complete_child_pin_login",
      {
        p_actor_id: user.id,
        p_child_id: body.childId,
        p_challenge_id: challenge.challengeId,
        p_credential_updated_at: challenge.credentialUpdatedAt,
        p_matches: difference === 0,
        p_token_hash: await sha256(accessToken),
      },
    );
    if (finishError || !session) return fail(503, "STORAGE_UNAVAILABLE");
    if (session.error) return rpcFailure(session);
    return reply(201, { ...session, accessToken });
  } catch {
    return fail(500, "INTERNAL_ERROR");
  }
});
