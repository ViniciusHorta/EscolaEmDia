import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "http://localhost:8081", "http://127.0.0.1:8081",
  "http://localhost:8080", "http://127.0.0.1:8080",
]);
const iterations = 600_000;
const encoder = new TextEncoder();
const sha256 = async (value: string) => hex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  // Hosted and local gateways may include /functions/v1 in the request pathname.
  const route = new URL(req.url).pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/parent-pin(?=\/|$)/, "");
  const operation = route === "/v1/status" ? "status"
    : route === "/v1/setup" ? "setup"
    : route === "/v1/verify" ? "verify"
    : route === "/v1/unlock-status" ? "unlock-status"
    : route === "/v1/touch" ? "touch"
    : route === "/v1/revoke" ? "revoke" : "unknown";
  const origin = req.headers.get("origin");
  const cors: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-parent-unlock",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Expose-Headers": "X-Request-Id, Retry-After",
    "Vary": "Origin",
  };
  if (origin && allowedOrigins.has(origin)) cors["Access-Control-Allow-Origin"] = origin;
  const reply = (status: number, value: unknown, code?: string) => {
    // Fixed operation names and correlation IDs only: no bodies or credentials.
    console.info(JSON.stringify({ requestId, domain: "parent-pin", operation, status, ...(code ? { code } : {}) }));
    return new Response(JSON.stringify(value), {
      status,
      headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store", "X-Request-Id": requestId },
    });
  };
  const messages: Record<string, string> = {
    ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
    ROUTE_NOT_FOUND: "Endereço não encontrado.",
    METHOD_NOT_ALLOWED: "Método não permitido para este endereço.",
    SERVICE_NOT_CONFIGURED: "A configuração do PIN está temporariamente indisponível.",
    AUTH_REQUIRED: "A tua sessão terminou. Entra novamente na conta.",
    EMAIL_NOT_CONFIRMED: "Confirma o teu e-mail antes de configurar o PIN.",
    JSON_REQUIRED: "O pedido deve usar application/json.",
    INVALID_REQUEST: "O pedido é inválido.",
    REQUEST_TOO_LARGE: "O pedido excede o tamanho permitido.",
    STORAGE_UNAVAILABLE: "Não foi possível aceder aos dados do PIN. Tenta mais tarde.",
    PIN_ALREADY_CONFIGURED: "O PIN desta conta já está configurado.",
    INVALID_PIN: "O PIN deve ter exatamente 4 dígitos.",
    WRONG_PIN: "O PIN parental não está correto. Tenta novamente.",
    PIN_LOCKED: "Demasiadas tentativas. Aguarda cinco minutos antes de tentar novamente.",
    PIN_BUSY: "Já existe uma tentativa em curso. Aguarda alguns instantes.",
    VERIFY_EXPIRED: "A tentativa expirou. Introduz o PIN novamente.",
    PIN_NOT_CONFIGURED: "Configura primeiro o teu PIN parental.",
    PARENT_LOCKED: "A área dos pais está bloqueada. Introduz o PIN parental.",
    INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
  };
  const fail = (status: number, code: string, retryAfter?: number) => {
    const response = reply(status, {
      error: { code, message: messages[code] ?? messages.INTERNAL_ERROR, requestId,
        ...(retryAfter ? { details: { retryAfter } } : {}) },
    }, code);
    if (retryAfter) response.headers.set("Retry-After", String(retryAfter));
    return response;
  };
  const rpcFailure = (data: Record<string, unknown>) => {
    const code = typeof data.error === "string" ? data.error : "STORAGE_UNAVAILABLE";
    const status = code === "PIN_LOCKED" ? 429 : code === "WRONG_PIN" || code === "AUTH_REQUIRED" ? 401
      : code === "PARENT_LOCKED" ? 403 : code === "PIN_BUSY" || code === "VERIFY_EXPIRED" || code === "PIN_NOT_CONFIGURED" ? 409 : 503;
    return fail(status, code, typeof data.retryAfter === "number" ? data.retryAfter : undefined);
  };

  if (origin && !allowedOrigins.has(origin)) return fail(403, "ORIGIN_NOT_ALLOWED");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (operation === "unknown") return fail(404, "ROUTE_NOT_FOUND");
  if (req.method !== ((operation === "status" || operation === "unlock-status") ? "GET" : "POST")) {
    return fail(405, "METHOD_NOT_ALLOWED");
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serverKey) return fail(503, "SERVICE_NOT_CONFIGURED");
    const authorization = req.headers.get("authorization") ?? "";
    const match = /^Bearer (\S+)$/i.exec(authorization);
    if (!match) return fail(401, "AUTH_REQUIRED");

    // Never decode a JWT and trust its claims without server-side validation.
    const admin = createClient(url, serverKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data: { user }, error: authError } = await admin.auth.getUser(match[1]);
    if (authError || !user) return fail(401, "AUTH_REQUIRED");
    if (!user.email_confirmed_at) return fail(403, "EMAIL_NOT_CONFIRMED");

    // Decode session_id only AFTER Auth has validated this exact JWT.
    let authSessionId: string | undefined;
    try {
      const encoded = match[1].split(".")[1].replace(/-/g,"+").replace(/_/g,"/");
      const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length/4)*4,"=")));
      if (claims.sub === user.id && typeof claims.session_id === "string"
        && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(claims.session_id)) authSessionId = claims.session_id;
    } catch { /* No unverified claims are used. */ }
    if (operation !== "status" && operation !== "setup" && !authSessionId) return fail(401,"AUTH_REQUIRED");
    if (["unlock-status","touch","revoke"].includes(operation)) {
      const unlockToken = req.headers.get("x-parent-unlock") ?? "";
      if (!/^par_[0-9a-f]{64}$/.test(unlockToken)) return fail(403,"PARENT_LOCKED");
      const { data, error } = await admin.rpc("use_parent_unlock", {
        p_actor_id:user.id,p_auth_session_id:authSessionId,p_token_hash:await sha256(unlockToken),
        p_touch:operation === "touch",p_revoke:operation === "revoke",
      });
      if (error || !data) return fail(503,"STORAGE_UNAVAILABLE");
      if (data.error) return rpcFailure(data);
      return reply(200,data);
    }

    // Account identity always comes from Auth; never accept a user ID in the body.
    const { data: existing, error: lookupError } = await admin
      .from("adult_pin_credentials").select("adult_user_id").eq("adult_user_id", user.id).maybeSingle();
    if (lookupError) return fail(503, "STORAGE_UNAVAILABLE");
    if (operation === "status") return reply(200, { configured: existing !== null });
    if (operation === "setup" && existing) return fail(409, "PIN_ALREADY_CONFIGURED");

    if (!req.headers.get("content-type")?.includes("application/json")) {
      return fail(415, "JSON_REQUIRED");
    }
    // Cap even streamed/chunked payloads; PIN requests need only a few bytes.
    const reader = req.body?.getReader();
    if (!reader) return fail(400, "INVALID_REQUEST");
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1024) {
        await reader.cancel();
        return fail(413, "REQUEST_TOO_LARGE");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    let body;
    try { body = JSON.parse(new TextDecoder().decode(bytes)); }
    catch { return fail(400, "INVALID_REQUEST"); }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return fail(400, "INVALID_REQUEST");
    }
    if (Object.keys(body).some((key) => key !== "pin")) {
      return fail(400, "INVALID_REQUEST");
    }

    if (typeof body.pin !== "string" || !/^[0-9]{4}$/.test(body.pin)) {
      return fail(422, "INVALID_PIN");
    }

    const pepper = Deno.env.get("PARENT_PIN_PEPPER");
    if (!pepper || pepper.length < 32) return fail(503, "SERVICE_NOT_CONFIGURED");
    if (operation === "verify") {
      const {data:challenge,error:startError} = await admin.rpc("begin_parent_pin_verify",{p_actor_id:user.id});
      if (startError || !challenge) return fail(503,"STORAGE_UNAVAILABLE");
      if (challenge.error) return rpcFailure(challenge);
      if (challenge.algorithm !== "pbkdf2-sha256-hmac-pepper-v1" || challenge.iterations !== 600000
        || !/^[0-9a-f]{32}$/.test(challenge.salt) || !/^[0-9a-f]{64}$/.test(challenge.hash)) return fail(503,"STORAGE_UNAVAILABLE");
      const pepperKey = await crypto.subtle.importKey("raw",encoder.encode(pepper),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
      const preHash = await crypto.subtle.sign("HMAC",pepperKey,encoder.encode(`parent-pin-v1:${user.id}:${body.pin}`));
      const material = await crypto.subtle.importKey("raw",preHash,"PBKDF2",false,["deriveBits"]);
      const salt = Uint8Array.from(challenge.salt.match(/../g)!, (value:string) => parseInt(value,16));
      const bits = await crypto.subtle.deriveBits({name:"PBKDF2",hash:"SHA-256",salt,iterations:challenge.iterations},material,256);
      const candidate = hex(new Uint8Array(bits)); let difference = 0;
      for (let i=0;i<64;i++) difference |= candidate.charCodeAt(i)^challenge.hash.charCodeAt(i);
      const unlockToken = `par_${hex(crypto.getRandomValues(new Uint8Array(32)))}`;
      const {data,error} = await admin.rpc("complete_parent_pin_verify",{
        p_actor_id:user.id,p_auth_session_id:authSessionId,p_challenge_id:challenge.challengeId,
        p_credential_updated_at:challenge.credentialUpdatedAt,p_matches:difference===0,p_token_hash:await sha256(unlockToken),
      });
      if (error || !data) return fail(503,"STORAGE_UNAVAILABLE");
      if (data.error) return rpcFailure(data);
      return reply(200,{...data,unlockToken});
    }

    // The pepper remains outside the database. Salt is random per credential.
    const pepperKey = await crypto.subtle.importKey(
      "raw", encoder.encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
    );
    const preHash = await crypto.subtle.sign(
      "HMAC", pepperKey, encoder.encode(`parent-pin-v1:${user.id}:${body.pin}`),
    );
    const material = await crypto.subtle.importKey("raw", preHash, "PBKDF2", false, ["deriveBits"]);
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const hash = await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt, iterations }, material, 256,
    );
    const { error: insertError } = await admin.from("adult_pin_credentials").insert({
      adult_user_id: user.id,
      pin_hash: hex(new Uint8Array(hash)),
      salt: hex(salt),
      iterations,
      algorithm: "pbkdf2-sha256-hmac-pepper-v1",
    });
    // A unique key makes concurrent requests safe; no existing PIN is overwritten.
    if (insertError?.code === "23505") return fail(409, "PIN_ALREADY_CONFIGURED");
    if (insertError) return fail(503, "STORAGE_UNAVAILABLE");
    return reply(201, { configured: true });
  } catch {
    // Do not log PINs, request bodies, hashes or credentials, including on failure.
    return fail(500, "INTERNAL_ERROR");
  }
});
