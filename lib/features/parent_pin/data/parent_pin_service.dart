import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/data/reauthentication.dart';

class ParentPinException implements Exception {
  const ParentPinException(this.message, {this.alreadyConfigured = false, this.reauthRequired = false, this.requestId});
  final String message;
  final bool alreadyConfigured;
  final bool reauthRequired;
  final String? requestId;
}

class ParentPinService {
  const ParentPinService(this.client);
  final SupabaseClient client;

  Future<bool> isConfigured() async {
    final result = await _request('status', method: HttpMethod.get);
    return result['configured'] == true;
  }

  Future<void> setup(String pin) async {
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const ParentPinException('O PIN deve ter exatamente 4 dígitos.');
    }
    final result = await _request('setup', body: {'pin': pin});
    if (result['configured'] != true) {
      throw const ParentPinException('Não foi possível confirmar a gravação do PIN. Tenta novamente.');
    }
  }

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
      throw ParentPinException(error.message);
    }
  }

  /// Substitui o PIN do responsável. Só é aceite até cinco minutos após uma reautenticação
  /// ([reauthenticate] ou [reauthenticateWithCode]).
  Future<void> reset(String pin) async {
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const ParentPinException('O PIN deve ter exatamente 4 dígitos.');
    }
    final result = await _request('reset', body: {'pin': pin});
    if (result['configured'] != true) {
      throw const ParentPinException('Não foi possível confirmar o novo PIN. Tenta novamente.');
    }
  }

  Future<Map> _request(String operation, {HttpMethod method = HttpMethod.post, Map<String, dynamic>? body}) async {
    try {
      // Explicitly use an adult session JWT, never the public project key as a bearer token.
      var session = client.auth.currentSession;
      if (session == null) {
        throw const ParentPinException('A tua sessão terminou. Entra novamente na conta.');
      }
      if (session.isExpired) {
        session = (await client.auth.refreshSession()).session;
      }
      if (session == null) {
        throw const ParentPinException('A tua sessão terminou. Entra novamente na conta.');
      }
      final response = await client.functions.invoke(
        'parent-pin/v1/$operation',
        method: method,
        body: body,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final data = response.data;
      if (data is! Map || data['configured'] is! bool) {
        throw const ParentPinException('Não foi possível confirmar o estado do PIN. Tenta novamente.');
      }
      return data;
    } on ParentPinException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final payload = details is Map ? details['error'] : null;
      final code = payload is Map ? payload['code'] : null;
      final message = payload is Map ? payload['message'] : null;
      final requestId = payload is Map ? payload['requestId'] : null;
      // API messages are written for users. Never show raw SDK or database errors.
      throw ParentPinException(
        message is String && message.isNotEmpty
            ? message
            : 'Não foi possível aceder ao PIN do responsável. Tenta novamente.',
        alreadyConfigured: code == 'PIN_ALREADY_CONFIGURED',
        reauthRequired: code == 'REAUTH_REQUIRED',
        requestId: requestId is String ? requestId : null,
      );
    } on AuthException {
      throw const ParentPinException('Não foi possível renovar a sessão. Entra novamente na conta.');
    } catch (_) {
      throw const ParentPinException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
  }
}
