// Vários responsáveis por família: listar, convidar (com email), cancelar convite,
// remover/sair, ver e aceitar convite. As regras vivem nas funções SQL family_*.
//
//   GET    /v1/families/{familyId}/members                       auth
//   POST   /v1/families/{familyId}/invitations   {email}         auth + desbloqueio
//   DELETE /v1/families/{familyId}/invitations/{invitationId}    auth + desbloqueio
//   DELETE /v1/families/{familyId}/members/{adultUserId}         auth + desbloqueio
//   GET    /v1/invitations/{token}                               público (o token é o segredo)
//   POST   /v1/invitations/{token}/accept                        auth (email do convite)
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { checkParentUnlock, sha256Hex } from "../_shared/parent_unlock.ts";
import { readEmailConfig, sendEmail } from "../_shared/sendpulse.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const inviteToken = /^inv_[0-9a-f]{64}$/;

export const memberMessages: Record<string, string> = {
  ALREADY_MEMBER: "Este adulto já é responsável desta família.",
  MEMBER_LIMIT: "Uma família pode ter até 4 responsáveis (incluindo convites pendentes).",
  RATE_LIMITED: "Foram enviados demasiados convites. Tenta novamente amanhã.",
  INVITATION_INVALID: "Este convite já não é válido. Pede um novo convite.",
  INVITATION_EXPIRED: "Este convite expirou. Pede um novo convite.",
  INVITATION_EMAIL_MISMATCH:
    "Este convite foi enviado para outro e-mail. Entra com a conta desse e-mail.",
  ALREADY_IN_FAMILY:
    "A tua conta já pertence a uma família com crianças. Uma conta só pode estar numa família.",
  MEMBER_NOT_FOUND: "Este responsável já não pertence à família.",
  LAST_MEMBER: "A família precisa de ter pelo menos um responsável.",
  EMAIL_UNAVAILABLE: "Não foi possível enviar o e-mail do convite. Tenta novamente.",
};

const statusFor: Record<string, number> = {
  INVALID_REQUEST: 400, AUTH_REQUIRED: 401, ADULT_SETUP_REQUIRED: 403,
  INVITATION_EMAIL_MISMATCH: 403, FAMILY_NOT_FOUND: 404, INVITATION_INVALID: 404,
  MEMBER_NOT_FOUND: 404, ALREADY_MEMBER: 409, MEMBER_LIMIT: 409, ALREADY_IN_FAMILY: 409,
  LAST_MEMBER: 409, INVITATION_EXPIRED: 410, RATE_LIMITED: 429,
};

type Route =
  | { kind: "list" | "invite"; familyId: string }
  | { kind: "cancel"; familyId: string; invitationId: string }
  | { kind: "remove"; familyId: string; adultUserId: string }
  | { kind: "preview" | "accept"; token: string };

export function matchMembersRoute(path: string): Route | null {
  let m = /^\/v1\/families\/([^/]+)\/members$/.exec(path);
  if (m) return { kind: "list", familyId: m[1] };
  if ((m = /^\/v1\/families\/([^/]+)\/invitations$/.exec(path))) return { kind: "invite", familyId: m[1] };
  if ((m = /^\/v1\/families\/([^/]+)\/invitations\/([^/]+)$/.exec(path)))
    return { kind: "cancel", familyId: m[1], invitationId: m[2] };
  if ((m = /^\/v1\/families\/([^/]+)\/members\/([^/]+)$/.exec(path)))
    return { kind: "remove", familyId: m[1], adultUserId: m[2] };
  if ((m = /^\/v1\/invitations\/([^/]+)$/.exec(path))) return { kind: "preview", token: m[1] };
  if ((m = /^\/v1\/invitations\/([^/]+)\/accept$/.exec(path))) return { kind: "accept", token: m[1] };
  return null;
}

const methodFor: Record<Route["kind"], string> = {
  list: "GET", invite: "POST", cancel: "DELETE", remove: "DELETE", preview: "GET", accept: "POST",
};

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function invitationEmail(to: string, inviter: string, link: string) {
  const subject = "Convite para a família no Escola em Dia";
  const text = [
    "Olá!",
    "",
    `${inviter} convidou-te para seres responsável de uma família no Escola em Dia.`,
    "Como responsável, podes acompanhar as fichas e o progresso das crianças.",
    "",
    `Aceita o convite aqui (válido durante 7 dias): ${link}`,
    "",
    "Se não estavas à espera deste convite, podes ignorar este e-mail.",
  ].join("\n");
  const html = `<!doctype html><html lang="pt"><body style="margin:0;padding:24px;background:#f6f7fb;font-family:Arial,Helvetica,sans-serif;color:#1f2937">
<table role="presentation" width="100%" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:16px;padding:32px">
<tr><td>
<h1 style="font-size:22px;margin:0 0 16px">Convite para a família</h1>
<p style="font-size:16px;line-height:1.5;margin:0 0 12px"><strong>${escapeHtml(inviter)}</strong> convidou-te para seres responsável de uma família no Escola em Dia.</p>
<p style="font-size:16px;line-height:1.5;margin:0 0 24px">Como responsável, podes acompanhar as fichas e o progresso das crianças.</p>
<p style="margin:0 0 24px"><a href="${escapeHtml(link)}" style="display:inline-block;background:#4f46e5;color:#ffffff;text-decoration:none;font-weight:bold;padding:14px 24px;border-radius:10px">Aceitar convite</a></p>
<p style="font-size:13px;line-height:1.5;color:#6b7280;margin:0">O convite é válido durante 7 dias e só pode ser aceite com a conta ${escapeHtml(to)}. Se não estavas à espera deste convite, podes ignorar este e-mail.</p>
</td></tr></table></body></html>`;
  return { subject, text, html };
}

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  if (!req.headers.get("content-type")?.includes("application/json")) return null;
  const raw = await req.text();
  if (raw.length > 2048) return null;
  try {
    const body = JSON.parse(raw);
    return body && typeof body === "object" && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

type Reply = (status: number, data: unknown) => Response;
type Fail = (status: number, code: string) => Response;

export async function handleMembers(req: Request, route: Route, reply: Reply, fail: Fail) {
  if (req.method !== methodFor[route.kind]) return fail(405, "METHOD_NOT_ALLOWED");
  if ("familyId" in route && !uuid.test(route.familyId)) return fail(400, "INVALID_REQUEST");
  if (route.kind === "cancel" && !uuid.test(route.invitationId)) return fail(400, "INVALID_REQUEST");
  if (route.kind === "remove" && !uuid.test(route.adultUserId)) return fail(400, "INVALID_REQUEST");
  if ("token" in route && !inviteToken.test(route.token)) return fail(404, "INVITATION_INVALID");

  const projectUrl = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectUrl || !key) return fail(503, "SERVICE_NOT_CONFIGURED");
  const admin: SupabaseClient = createClient(projectUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const rpcFail = (error: { message: string }) =>
    statusFor[error.message] ? fail(statusFor[error.message], error.message) : fail(503, "STORAGE_UNAVAILABLE");

  // Ver o convite não exige sessão: o ecrã aparece antes de entrar/criar conta.
  if (route.kind === "preview") {
    const { data, error } = await admin.rpc("family_invitation_preview", { p_token_hash: await sha256Hex(route.token) });
    if (error || !data) return fail(503, "STORAGE_UNAVAILABLE");
    if (data.status === "invalid") return fail(404, "INVITATION_INVALID");
    return reply(200, data);
  }

  const accessToken = /^Bearer (\S+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
  if (!accessToken || accessToken.startsWith("chd_")) return fail(401, "AUTH_REQUIRED");
  const { data: { user }, error: authError } = await admin.auth.getUser(accessToken);
  if (authError || !user) return fail(401, "AUTH_REQUIRED");
  if (!user.email_confirmed_at) return fail(403, "EMAIL_NOT_CONFIRMED");

  if (route.kind === "accept") {
    const { data, error } = await admin.rpc("family_accept_invitation", {
      p_actor_id: user.id, p_token_hash: await sha256Hex(route.token),
    });
    if (error) return rpcFail(error);
    return reply(200, data);
  }

  if (route.kind === "list") {
    const { data, error } = await admin.rpc("family_list_members", { p_actor_id: user.id, p_family_id: route.familyId });
    if (error) return rpcFail(error);
    return reply(200, data);
  }

  // Alterações à família exigem a área do responsável desbloqueada.
  const locked = await checkParentUnlock(admin, req, accessToken, user.id);
  if (locked) return fail(locked.status, locked.code);

  if (route.kind === "cancel") {
    const { data, error } = await admin.rpc("family_cancel_invitation", {
      p_actor_id: user.id, p_family_id: route.familyId, p_invitation_id: route.invitationId,
    });
    if (error) return rpcFail(error);
    return reply(200, data);
  }

  if (route.kind === "remove") {
    const { data, error } = await admin.rpc("family_remove_member", {
      p_actor_id: user.id, p_family_id: route.familyId, p_adult_user_id: route.adultUserId,
    });
    if (error) return rpcFail(error);
    return reply(200, data);
  }

  if (route.kind !== "invite") return fail(404, "ROUTE_NOT_FOUND");
  const body = await readJson(req);
  if (!body || Object.keys(body).some((k) => k !== "email") || typeof body.email !== "string")
    return fail(400, "INVALID_REQUEST");
  const emailConfig = readEmailConfig();
  if (!emailConfig) return fail(503, "EMAIL_UNAVAILABLE");
  const token = "inv_" + Array.from(crypto.getRandomValues(new Uint8Array(32)),
    (b) => b.toString(16).padStart(2, "0")).join("");
  const { data: invitation, error } = await admin.rpc("family_invite_adult", {
    p_actor_id: user.id, p_family_id: route.familyId, p_email: body.email, p_token_hash: await sha256Hex(token),
  });
  if (error) return rpcFail(error);
  const base = Deno.env.get("INVITE_BASE_URL") ?? "https://app.escolaemdia.me/convite";
  const link = `${base}?token=${token}`;
  try {
    await sendEmail({ to: { email: invitation.email }, ...invitationEmail(invitation.email, user.email ?? "Um responsável", link) }, emailConfig);
  } catch (e) {
    // Sem email o convite é inútil: cancela-o para não ocupar vaga.
    console.error(JSON.stringify({ domain: "families", operation: "members", emailError: String(e) }));
    await admin.rpc("family_cancel_invitation", {
      p_actor_id: user.id, p_family_id: route.familyId, p_invitation_id: invitation.id,
    });
    return fail(503, "EMAIL_UNAVAILABLE");
  }
  return reply(201, invitation);
}
