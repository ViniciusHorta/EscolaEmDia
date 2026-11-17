// Envio de emails transacionais pela SMTP API do SendPulse (sem SDK).
// Segredos: SENDPULSE_CLIENT_ID, SENDPULSE_CLIENT_SECRET (Definições da conta → API),
// EMAIL_FROM_ADDRESS (remetente verificado no SendPulse SMTP) e EMAIL_FROM_NAME (opcional).
export class EmailError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export type EmailMessage = {
  to: { email: string; name?: string };
  subject: string;
  html: string;
  text: string;
};

type Config = { clientId: string; clientSecret: string; fromEmail: string; fromName: string };

const API = "https://api.sendpulse.com";
let cached: { token: string; expires: number } | null = null;

export function readEmailConfig(): Config | null {
  const clientId = Deno.env.get("SENDPULSE_CLIENT_ID");
  const clientSecret = Deno.env.get("SENDPULSE_CLIENT_SECRET");
  const fromEmail = Deno.env.get("EMAIL_FROM_ADDRESS");
  if (!clientId || !clientSecret || !fromEmail) return null;
  return { clientId, clientSecret, fromEmail, fromName: Deno.env.get("EMAIL_FROM_NAME") ?? "Escola em Dia" };
}

// O SendPulse exige o HTML em base64; btoa sozinho estraga acentos, por isso passa por UTF-8.
export const base64Utf8 = (value: string) => {
  let s = "";
  for (const b of new TextEncoder().encode(value)) s += String.fromCharCode(b);
  return btoa(s);
};

async function accessToken(config: Config) {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const res = await fetch(`${API}/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "client_credentials",
      client_id: config.clientId,
      client_secret: config.clientSecret,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) throw new EmailError(res.status, `oauth: ${body.error ?? res.status}`);
  cached = { token: body.access_token, expires: Date.now() + (body.expires_in ?? 3600) * 1000 };
  return cached.token;
}

export async function sendEmail(message: EmailMessage, config = readEmailConfig()) {
  if (!config) throw new EmailError(503, "email não configurado");
  const send = async (token: string) =>
    await fetch(`${API}/smtp/emails`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        email: {
          subject: message.subject,
          html: base64Utf8(message.html),
          text: message.text,
          from: { name: config.fromName, email: config.fromEmail },
          to: [{ email: message.to.email, ...(message.to.name ? { name: message.to.name } : {}) }],
        },
      }),
    });
  let res = await send(await accessToken(config));
  if (res.status === 401) {
    cached = null; // token revogado antes do prazo: renova uma vez
    res = await send(await accessToken(config));
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.result === false) {
    throw new EmailError(res.status, `smtp: ${body.message ?? body.error_code ?? res.status}`);
  }
}
