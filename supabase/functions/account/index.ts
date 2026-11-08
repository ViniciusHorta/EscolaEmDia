import { createCors } from "../_shared/cors.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Eliminação da conta do responsável e de todos os dados associados.
// Exige uma reautenticação com palavra-passe nos últimos cinco minutos (amr do JWT),
// tal como a redefinição do PIN: uma criança com o dispositivo desbloqueado não consegue
// apagar a conta sem saber a palavra-passe do adulto.

const messages: Record<string, string> = {
  CORS_NOT_CONFIGURED:
    "A configuração de acesso está temporariamente indisponível.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido para este endereço.",
  SERVICE_NOT_CONFIGURED:
    "A eliminação de contas está temporariamente indisponível.",
  AUTH_REQUIRED: "A tua sessão terminou. Entra novamente na conta.",
  REAUTH_REQUIRED:
    "Confirma novamente a palavra-passe da conta para a eliminar.",
  JSON_REQUIRED: "O pedido deve usar application/json.",
  INVALID_REQUEST: "O pedido é inválido.",
  CONFIRMATION_REQUIRED: "Escreve ELIMINAR para confirmar.",
  STORAGE_UNAVAILABLE:
    "Não foi possível eliminar a conta. Tenta novamente dentro de momentos.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const route = new URL(req.url).pathname
    .replace(/^\/functions\/v1(?=\/)/, "")
    .replace(/^\/account(?=\/|$)/, "");
  const operation = route === "/v1/delete" ? "delete" : "unknown";
  const corsPolicy = createCors(req, { methods: "POST, OPTIONS" });
  const reply = (status: number, value: unknown, code?: string) => {
    // Só nomes de operação e ids de correlação: nunca e-mails, ids de conta ou corpos.
    console.info(
      JSON.stringify({
        requestId,
        domain: "account",
        operation,
        status,
        ...(code ? { code } : {}),
      }),
    );
    return new Response(JSON.stringify(value), {
      status,
      headers: {
        ...corsPolicy.headers,
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
  if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED");

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serverKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serverKey) return fail(503, "SERVICE_NOT_CONFIGURED");
    const token = /^Bearer (\S+)$/i.exec(
      req.headers.get("authorization") ?? "",
    )?.[1];
    if (!token || token.startsWith("chd_")) return fail(401, "AUTH_REQUIRED");

    const admin = createClient(url, serverKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
    // Identidade sempre a partir do Auth; nunca de um id enviado no corpo.
    const {
      data: { user },
      error: authError,
    } = await admin.auth.getUser(token);
    if (authError || !user) return fail(401, "AUTH_REQUIRED");

    // Só depois de o Auth validar este JWT se leem as suas claims.
    let passwordAuthAt: number | undefined;
    try {
      const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const claims = JSON.parse(
        atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")),
      );
      if (claims.sub === user.id && Array.isArray(claims.amr)) {
        for (const entry of claims.amr) {
          if (
            entry?.method === "password" &&
            typeof entry.timestamp === "number" &&
            (passwordAuthAt === undefined || entry.timestamp > passwordAuthAt)
          )
            passwordAuthAt = entry.timestamp;
        }
      }
    } catch {
      /* Sem claims válidas, a reautenticação falha abaixo. */
    }
    const age = Date.now() / 1000 - (passwordAuthAt ?? 0);
    if (passwordAuthAt === undefined || age < -60 || age > 300)
      return fail(401, "REAUTH_REQUIRED");

    if (!req.headers.get("content-type")?.includes("application/json"))
      return fail(415, "JSON_REQUIRED");
    const text = await req.text();
    if (text.length > 256) return fail(400, "INVALID_REQUEST");
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return fail(400, "INVALID_REQUEST");
    }
    if (
      !body ||
      typeof body !== "object" ||
      Array.isArray(body) ||
      Object.keys(body).some((key) => key !== "confirmation")
    )
      return fail(400, "INVALID_REQUEST");
    if (body.confirmation !== "ELIMINAR")
      return fail(422, "CONFIRMATION_REQUIRED");

    // 1) Dados da aplicação (famílias, crianças, histórico). Idempotente.
    const { data, error } = await admin.rpc("delete_account_data", {
      p_actor_id: user.id,
    });
    if (error || !data || data.error) return fail(503, "STORAGE_UNAVAILABLE");

    // 2) A conta em si. Apaga em cascata aceites legais, PIN, desbloqueios e relatos.
    // Se falhar, os dados já foram apagados e repetir o pedido termina a eliminação.
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) return fail(503, "STORAGE_UNAVAILABLE");

    return reply(200, { deleted: true, ...data });
  } catch {
    return fail(500, "INTERNAL_ERROR");
  }
});
