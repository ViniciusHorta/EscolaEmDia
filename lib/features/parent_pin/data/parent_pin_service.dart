import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Reautenticação: novo início de sessão com a palavra-passe da conta atual.
  /// O JWT resultante tem amr=password recente, exigido por [reset].
  Future<void> reauthenticate(String password) async {
    final email = client.auth.currentUser?.email;
    if (email == null) {
      throw const ParentPinException('A tua sessão terminou. Entra novamente na conta.');
    }
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw ParentPinException(
        error.statusCode == '429'
            ? 'Demasiadas tentativas. Aguarda um pouco antes de tentar novamente.'
            : error.code == 'invalid_credentials'
                ? 'A palavra-passe não está correta.'
                : 'Não foi possível confirmar a palavra-passe. Tenta novamente.',
      );
    } catch (_) {
      throw const ParentPinException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
  }

  /// Substitui o PIN parental. Só é aceite até cinco minutos após [reauthenticate].
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
            : 'Não foi possível aceder ao PIN parental. Tenta novamente.',
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
