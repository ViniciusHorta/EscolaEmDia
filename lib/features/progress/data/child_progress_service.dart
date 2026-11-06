import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/child_progress_models.dart';

class ChildProgressException implements Exception {
  const ChildProgressException(this.message);
  final String message;
}
class ChildProgressService {
  const ChildProgressService(this.client, {required this.parentToken, required this.onParentLocked});
  final SupabaseClient client;
  final String? Function() parentToken;
  final void Function() onParentLocked;

  Future<ChildProgress> overview(String childId) async {
    final result = ChildProgress.fromJson(await _request('/v1/children/$childId/progress'));
    if (result.child.id != childId) throw const ChildProgressException('Não foi possível confirmar o perfil consultado.');
    return result;
  }
  Future<AttemptHistoryPage> history(String childId, {String? cursor, String? subjectId, String? status}) async {
    final result = AttemptHistoryPage.fromJson(await _request('/v1/children/$childId/attempts', query: {
      if (cursor != null) 'cursor': cursor, if (subjectId != null) 'subjectId': subjectId, if (status != null) 'status': status,
    }));
    if (result.items.any((item) => item.childId != childId)) throw const ChildProgressException('Não foi possível confirmar o histórico deste perfil.');
    return result;
  }
  Future<Map> _request(String path, {Map<String, dynamic>? query}) async {
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null) {
        onParentLocked();
        throw const ChildProgressException('A tua sessão terminou. Entra novamente na conta.');
      }
      final capability = parentToken();
      if (capability == null) {
        onParentLocked();
        throw const ChildProgressException('Desbloqueia a área do responsável para continuar.');
      }
      final response = await client.functions.invoke('progress$path', method: HttpMethod.get, queryParameters: query,
        headers: {'Authorization': 'Bearer ${session.accessToken}', 'X-Parent-Unlock': capability});
      if (response.data is! Map) throw const ChildProgressException('Não foi possível ler o acompanhamento.');
      return response.data as Map;
    } on ChildProgressException { rethrow; }
    on FunctionException catch (failure) {
      final error = failure.details is Map ? (failure.details as Map)['error'] : null;
      if (failure.status == 401 || (error is Map && error['code'] == 'PARENT_LOCKED')) onParentLocked();
      throw ChildProgressException(error is Map && error['message'] is String
        ? error['message'] as String : 'Não foi possível consultar o acompanhamento.');
    } catch (_) {
      throw const ChildProgressException('Não foi possível ligar ao serviço de acompanhamento. Tenta novamente.');
    }
  }
}
