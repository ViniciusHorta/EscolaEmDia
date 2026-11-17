// Verifica o desbloqueio da área do responsável (cabeçalho x-parent-unlock), ligado à
// sessão Auth do adulto. Igual à verificação feita nas restantes funções do responsável.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const sha256Hex = async (value: string) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");

// Devolve null quando está desbloqueado; senão o estado e o código de erro.
export async function checkParentUnlock(
  admin: SupabaseClient,
  req: Request,
  accessToken: string,
  userId: string,
): Promise<{ status: number; code: string } | null> {
  const unlock = req.headers.get("x-parent-unlock") ?? "";
  if (!/^par_[0-9a-f]{64}$/.test(unlock)) return { status: 403, code: "PARENT_LOCKED" };
  let sessionId: string | undefined;
  try {
    const encoded = accessToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
    if (claims.sub === userId && typeof claims.session_id === "string" && uuid.test(claims.session_id))
      sessionId = claims.session_id;
  } catch { /* o Auth já validou o JWT; sem sessão associada recusa-se */ }
  if (!sessionId) return { status: 401, code: "AUTH_REQUIRED" };
  const { data, error } = await admin.rpc("use_parent_unlock", {
    p_actor_id: userId, p_auth_session_id: sessionId, p_token_hash: await sha256Hex(unlock),
    p_touch: true, p_revoke: false,
  });
  if (error || !data) return { status: 503, code: "STORAGE_UNAVAILABLE" };
  if (data.error) return { status: 403, code: "PARENT_LOCKED" };
  return null;
}
