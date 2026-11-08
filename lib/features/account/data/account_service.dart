import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// Novo início de sessão com a palavra-passe. O JWT resultante tem amr=password recente,
  /// exigido por [deleteAccount] durante cinco minutos.
  Future<void> reauthenticate(String password) async {
    final email = client.auth.currentUser?.email;
    if (email == null) {
      throw const AccountException('A tua sessão terminou. Entra novamente na conta.');
    }
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw AccountException(
        error.statusCode == '429'
            ? 'Demasiadas tentativas. Aguarda um pouco antes de tentar novamente.'
            : error.code == 'invalid_credentials'
                ? 'A palavra-passe não está correta.'
                : 'Não foi possível confirmar a palavra-passe. Tenta novamente.',
      );
    } catch (_) {
      throw const AccountException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
  }

  /// Apaga a conta e os dados no servidor e, a seguir, a sessão e as preferências locais.
  /// Irreversível. Só é aceite até cinco minutos após [reauthenticate].
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
