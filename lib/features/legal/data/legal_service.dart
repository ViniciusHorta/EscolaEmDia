import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/legal_models.dart';

class LegalException implements Exception {
  const LegalException(this.message, {this.outdated = false});
  final String message;

  /// Foi publicada uma versão nova entre a leitura e o aceite.
  final bool outdated;
}

/// Documentos legais e aceites (Edge Function `legal`).
class LegalService {
  const LegalService(this.client);
  final SupabaseClient client;

  /// Versões em vigor. Não exige sessão: é usado no formulário de registo.
  Future<List<LegalDocument>> currentDocuments() async {
    final data = await _request('documents', method: HttpMethod.get, authenticated: false);
    final items = data['items'];
    if (items is! List) throw const LegalException('Não foi possível carregar os documentos legais.');
    return items.map(LegalDocument.tryParse).whereType<LegalDocument>().toList();
  }

  /// Uma versão concreta, por exemplo a que o responsável aceitou.
  Future<LegalDocument> document(String id) async {
    final document = LegalDocument.tryParse(
      await _request('documents/$id', method: HttpMethod.get, authenticated: false));
    if (document == null) throw const LegalException('Este documento não está disponível.');
    return document;
  }

  Future<LegalStatus> status() async => _status(await _request('acceptances', method: HttpMethod.get));

  Future<LegalStatus> accept(List<String> documentIds) async =>
      _status(await _request('acceptances', body: {'documentIds': documentIds}));

  LegalStatus _status(Map data) {
    final status = LegalStatus.tryParse(data);
    if (status == null) throw const LegalException('Não foi possível confirmar o estado dos documentos legais.');
    return status;
  }

  Future<Map> _request(String route, {HttpMethod method = HttpMethod.post, Map<String, dynamic>? body,
      bool authenticated = true}) async {
    try {
      final headers = <String, String>{};
      if (authenticated) {
        var session = client.auth.currentSession;
        if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
        if (session == null) throw const LegalException('A tua sessão terminou. Entra novamente na conta.');
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
      final response = await client.functions.invoke('legal/v1/$route', method: method, body: body, headers: headers);
      final data = response.data;
      if (data is! Map) throw const LegalException('Não foi possível carregar os documentos legais.');
      return data;
    } on LegalException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final payload = details is Map ? details['error'] : null;
      final code = payload is Map ? payload['code'] : null;
      final message = payload is Map ? payload['message'] : null;
      throw LegalException(
        message is String && message.isNotEmpty ? message : 'Não foi possível carregar os documentos legais.',
        outdated: code == 'DOCUMENT_OUTDATED',
      );
    } on AuthException {
      throw const LegalException('Não foi possível renovar a sessão. Entra novamente na conta.');
    } catch (_) {
      throw const LegalException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
  }
}
