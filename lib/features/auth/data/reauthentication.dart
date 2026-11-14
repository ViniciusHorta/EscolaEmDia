import 'package:supabase_flutter/supabase_flutter.dart';

class ReauthException implements Exception {
  const ReauthException(this.message);
  final String message;
}

/// Reautenticação recente exigida pelas ações sensíveis (redefinir o PIN do responsável,
/// eliminar a conta). O servidor aceita um JWT com `amr` password ou otp com menos de
/// cinco minutos (ver `supabase/functions/_shared/reauth.ts`).
///
/// Contas criadas com o Google não têm palavra-passe: confirmam com um código enviado
/// para o e-mail da conta. Quem tem palavra-passe também pode usar o código.
class Reauthentication {
  const Reauthentication(this.client);
  final SupabaseClient client;

  static const _offline = 'Não foi possível ligar ao serviço. Verifica a ligação à Internet.';

  String? get email => client.auth.currentUser?.email;

  /// Falso para contas só com Google (sem identidade `email`). Sem informação sobre as
  /// identidades, assume que há palavra-passe (comportamento anterior).
  bool get hasPassword {
    final identities = client.auth.currentUser?.identities;
    if (identities == null || identities.isEmpty) return true;
    return identities.any((identity) => identity.provider == 'email');
  }

  Future<void> withPassword(String password) async {
    final address = _requireEmail();
    try {
      await client.auth.signInWithPassword(email: address, password: password);
    } on AuthException catch (error) {
      throw ReauthException(_rateLimit(error) ??
          (error.code == 'invalid_credentials'
              ? 'A palavra-passe não está correta.'
              : 'Não foi possível confirmar a palavra-passe. Tenta novamente.'));
    } catch (_) {
      throw const ReauthException(_offline);
    }
  }

  /// Envia um código de uso único para o e-mail da conta (template «Magic Link» do
  /// Supabase, que tem de incluir `{{ .Token }}`). Nunca cria contas.
  Future<void> sendEmailCode() async {
    final address = _requireEmail();
    try {
      await client.auth.signInWithOtp(email: address, shouldCreateUser: false);
    } on AuthException catch (error) {
      throw ReauthException(_rateLimit(error) ?? 'Não foi possível enviar o código. Tenta novamente.');
    } catch (_) {
      throw const ReauthException(_offline);
    }
  }

  Future<void> withEmailCode(String code) async {
    final address = _requireEmail();
    final token = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9]{6,10}$').hasMatch(token)) {
      throw const ReauthException('Indica o código que recebeste por e-mail.');
    }
    try {
      await client.auth.verifyOTP(type: OtpType.email, email: address, token: token);
    } on AuthException catch (error) {
      throw ReauthException(_rateLimit(error) ??
          (error.code == 'otp_expired'
              ? 'O código não está correto ou expirou. Confirma o código ou pede um novo.'
              : 'Não foi possível confirmar o código. Tenta novamente.'));
    } catch (_) {
      throw const ReauthException(_offline);
    }
  }

  String _requireEmail() {
    final address = email;
    if (address == null) throw const ReauthException('A tua sessão terminou. Entra novamente na conta.');
    return address;
  }

  static String? _rateLimit(AuthException error) {
    if (error.code == 'over_email_send_rate_limit') {
      return 'Já enviámos um código há pouco. Aguarda um minuto antes de pedir outro.';
    }
    if (error.statusCode == '429' || error.code == 'over_request_rate_limit') {
      return 'Demasiadas tentativas. Aguarda um pouco antes de tentar novamente.';
    }
    return null;
  }
}
