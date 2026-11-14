// Métodos do `amr` do JWT aceites como reautenticação recente (≤ 5 min) para ações
// sensíveis: redefinir o PIN do responsável (`parent-pin`) e eliminar a conta (`account`).
//
// - "password": novo início de sessão com a palavra-passe da conta.
// - "otp" / "magiclink": código de uso único enviado para o e-mail da conta
//   (signInWithOtp + verifyOTP). É o caminho das contas criadas com o Google, que não
//   têm palavra-passe, e de quem se esqueceu dela. O GoTrue regista a verificação do
//   código de e-mail como "otp" ou "magiclink", consoante a versão; ambos provam acesso
//   à caixa de correio da conta.
//
// Uma sessão apenas antiga, renovada (token_refresh) ou aberta por OAuth não conta:
// uma criança com o dispositivo desbloqueado não tem acesso ao e-mail do adulto.
export const REAUTH_METHODS: ReadonlySet<string> = new Set([
  "password",
  "otp",
  "magiclink",
]);
