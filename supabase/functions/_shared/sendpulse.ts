// Envio de emails transacionais pelo SMTP do SendPulse.
// Segredos: SENDPULSE_SMTP_HOST (servidor, ex.: smtp-pulse.com), SENDPULSE_SMTP_PORT (2525 ou 465;
// as Edge Functions bloqueiam 25 e 587), SENDPULSE_SMTP_USER, SENDPULSE_SMTP_PASSWORD,
// EMAIL_FROM_ADDRESS (remetente verificado no SendPulse; por omissão SENDPULSE_SMTP_USER)
// e EMAIL_FROM_NAME (opcional).
// @deno-types="npm:@types/nodemailer@6.4.17"
import nodemailer from "npm:nodemailer@6.9.16";

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

type Config = {
  host: string; port: number; user: string; pass: string; fromEmail: string; fromName: string;
};

export function readEmailConfig(): Config | null {
  const host = Deno.env.get("SENDPULSE_SMTP_HOST");
  const user = Deno.env.get("SENDPULSE_SMTP_USER");
  const pass = Deno.env.get("SENDPULSE_SMTP_PASSWORD");
  const port = Number(Deno.env.get("SENDPULSE_SMTP_PORT") ?? "2525");
  if (!host || !user || !pass || !Number.isInteger(port) || port === 25 || port === 587) return null;
  return {
    host, port, user, pass,
    fromEmail: Deno.env.get("EMAIL_FROM_ADDRESS") || user,
    fromName: Deno.env.get("EMAIL_FROM_NAME") || "Escola em Dia",
  };
}

let transport: ReturnType<typeof nodemailer.createTransport> | null = null;

export async function sendEmail(message: EmailMessage, config = readEmailConfig()) {
  if (!config) throw new EmailError(503, "email não configurado");
  transport ??= nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.port === 465, // 465 = TLS direto; 2525 = STARTTLS obrigatório
    requireTLS: config.port !== 465,
    auth: { user: config.user, pass: config.pass },
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 15_000,
  });
  try {
    await transport.sendMail({
      from: { name: config.fromName, address: config.fromEmail },
      to: message.to.name ? { name: message.to.name, address: message.to.email } : message.to.email,
      subject: message.subject,
      text: message.text,
      html: message.html,
    });
  } catch (e) {
    transport = null; // a próxima tentativa abre uma ligação nova
    throw new EmailError(503, `smtp: ${(e as Error).message}`);
  }
}
