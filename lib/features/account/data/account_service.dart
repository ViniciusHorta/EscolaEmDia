import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/data/reauthentication.dart';
import '../../child_session/data/child_session_service.dart';
import '../../family/data/last_profile_store.dart';

class AccountException implements Exception {
  const AccountException(this.message, {this.reauthRequired = false});
  final String message;
  final bool reauthRequired;
}

/// Eliminação da conta do responsável (Edge Function `account`).
class AccountService {
  const AccountService(this.client);
  final SupabaseClient client;

  static const confirmationWord = 'ELIMINAR';

  Reauthentication get _reauth => Reauthentication(client);

  /// Falso para contas criadas só com o Google: confirmam com um código por e-mail.
  bool get hasPassword => _reauth.hasPassword;

  /// Reautenticação com a palavra-passe da conta (amr=password recente).
  Future<void> reauthenticate(String password) => _guard(() => _reauth.withPassword(password));

  /// Envia um código de verificação para o e-mail da conta.
  Future<void> sendReauthCode() => _guard(_reauth.sendEmailCode);

  /// Reautenticação com o código recebido por e-mail (amr=otp recente).
  Future<void> reauthenticateWithCode(String code) => _guard(() => _reauth.withEmailCode(code));

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ReauthException catch (error) {
      throw AccountException(error.message);
    }
  }

  /// Apaga a conta e os dados no servidor e, a seguir, a sessão e as preferências locais.
  /// Irreversível. Só é aceite até cinco minutos após uma reautenticação
  /// ([reauthenticate] ou [reauthenticateWithCode]).
  Future<void> deleteAccount() async {
    final adultId = client.auth.currentUser?.id;
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null || adultId == null) {
        throw const AccountException('A tua sessão terminou. Entra novamente na conta.');
      }
      final response = await client.functions.invoke(
        'account/v1/delete',
        body: {'confirmation': confirmationWord},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final data = response.data;
      if (data is! Map || data['deleted'] != true) {
        throw const AccountException('Não foi possível confirmar a eliminação. Tenta novamente.');
      }
    } on AccountException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final payload = details is Map ? details['error'] : null;
      final code = payload is Map ? payload['code'] : null;
      final message = payload is Map ? payload['message'] : null;
      throw AccountException(
        message is String && message.isNotEmpty ? message : 'Não foi possível eliminar a conta. Tenta novamente.',
        reauthRequired: code == 'REAUTH_REQUIRED',
      );
    } on AuthException {
      throw const AccountException('Não foi possível renovar a sessão. Entra novamente na conta.');
    } catch (_) {
      throw const AccountException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
    // A conta já não existe: limpar o que ficou neste dispositivo. Falhas aqui não
    // desfazem a eliminação, por isso são ignoradas.
    try {
      await ChildModeStore.clear(adultId);
      await LastProfileStore.clear(adultId);
    } catch (_) {}
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
