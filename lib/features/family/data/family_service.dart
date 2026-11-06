import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/family_models.dart';

class FamilyException implements Exception {
  const FamilyException(this.message, {this.requestId});
  final String message;
  final String? requestId;
}

class FamilyService {
  const FamilyService(this.client, {this.parentToken, this.onParentLocked});
  final SupabaseClient client;
  final String? Function()? parentToken;
  final void Function()? onParentLocked;

  Future<List<Family>> listFamilies() async =>
      (await _list('/v1/families')).map(Family.fromJson).toList();

  Future<List<ChildProfile>> listChildren(String familyId) async =>
      (await _list('/v1/families/$familyId/children')).map(ChildProfile.fromJson).toList();

  Future<Family> createFamily(String requestId) async => Family.fromJson(
    await _request('/v1/families', body: {'clientRequestId': requestId}),
  );

  Future<ChildProfile> createChild(String familyId, ChildProfileDraft draft) async => ChildProfile.fromJson(
    await _request('/v1/families/$familyId/children', body: {
      'clientRequestId': draft.requestId, 'displayName': draft.displayName,
      'schoolYear': draft.schoolYear, 'avatarId': draft.avatarId, 'pin': draft.pin,
    }),
  );

  /// Atualiza alcunha, ano e avatar. O PIN só é enviado quando o adulto o altera.
  Future<ChildProfile> updateChild(ChildProfile child, ChildProfileUpdate update) async => ChildProfile.fromJson(
    await _request('/v1/families/${child.familyId}/children/${child.id}', method: HttpMethod.put, body: {
      'displayName': update.displayName, 'schoolYear': update.schoolYear,
      'avatarId': update.avatarId, if (update.pin != null) 'pin': update.pin,
    }),
  );

  Future<List<Map>> _list(String path) async {
    final result = <Map>[];
    String? cursor;
    final seen = <String>{};
    do {
      final data = await _request(path, method: HttpMethod.get,
        query: cursor == null ? null : {'cursor': cursor});
      final items = data['items'];
      if (items is! List || items.any((item) => item is! Map)) {
        throw const FamilyException('Não foi possível ler os perfis. Tenta novamente.');
      }
      result.addAll(items.cast<Map>());
      final next = data['nextCursor'];
      if (next != null && (next is! String || !seen.add(next))) {
        throw const FamilyException('Não foi possível concluir a consulta. Tenta novamente.');
      }
      cursor = next as String?;
    } while (cursor != null);
    return result;
  }

  Future<Map> _request(String path, {HttpMethod method = HttpMethod.post,
    Map<String, dynamic>? body, Map<String, dynamic>? query}) async {
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null) throw const FamilyException('A tua sessão terminou. Entra novamente na conta.');
      final needsParent = method != HttpMethod.get;
      final capability = needsParent ? parentToken?.call() : null;
      if (needsParent && capability == null) {
        onParentLocked?.call();
        throw const FamilyException('Desbloqueia a área do responsável com o PIN do responsável.');
      }
      final response = await client.functions.invoke('families$path', method: method,
        body: body, queryParameters: query,
        headers: {'Authorization': 'Bearer ${session.accessToken}', if (capability != null) 'X-Parent-Unlock': capability});
      if (response.data is! Map) throw const FamilyException('Não foi possível confirmar o pedido. Tenta novamente.');
      return response.data as Map;
    } on FamilyException { rethrow; }
    on FunctionException catch (error) {
      final details = error.details;
      final payload = details is Map ? details['error'] : null;
      if (payload is Map && payload['code'] == 'PARENT_LOCKED') onParentLocked?.call();
      final message = payload is Map ? payload['message'] : null;
      final requestId = payload is Map ? payload['requestId'] : null;
      throw FamilyException(message is String ? message : 'Não foi possível aceder aos perfis. Tenta novamente.',
        requestId: requestId is String ? requestId : null);
    } on AuthException {
      throw const FamilyException('Não foi possível renovar a sessão. Entra novamente na conta.');
    } catch (_) {
      throw const FamilyException('Não foi possível ligar ao serviço. Verifica a ligação à Internet.');
    }
  }
}
