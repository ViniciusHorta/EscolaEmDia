import 'package:supabase_flutter/supabase_flutter.dart';
import '../../attempts/domain/submission_summary.dart';
import '../../family/domain/family_models.dart';
import '../domain/parent_review_models.dart';

class PendingReview {
  const PendingReview(this.child, this.summary);
  final ChildProfile child;
  final SubmissionSummary summary;
  factory PendingReview.fromJson(Map value) => PendingReview(
    ChildProfile.fromJson(value['child'] as Map), SubmissionSummary.fromJson(value),
  );
}
class PendingReviewsException implements Exception {
  const PendingReviewsException(this.message, {this.code, this.uncertain = false});
  final String message;
  final String? code;
  final bool uncertain;
}
class PendingReviewsService {
  const PendingReviewsService(this.client, {required this.parentToken, required this.onParentLocked});
  final SupabaseClient client;
  final String? Function() parentToken;
  final void Function() onParentLocked;

  Future<List<PendingReview>> list(String familyId, {bool completed = false}) async {
    final items = <PendingReview>[]; String? cursor; final seen = <String>{};
    do {
      final data = await _request('/v1/families/$familyId/${completed ? 'reviewed-attempts' : 'pending-reviews'}',
        query: cursor == null ? null : {'cursor': cursor});
      if (data['items'] is! List) throw const PendingReviewsException('Não foi possível carregar as revisões.');
      items.addAll((data['items'] as List).cast<Map>().map(PendingReview.fromJson));
      final next = data['nextCursor'];
      if (next != null && (next is! String || !seen.add(next))) throw const PendingReviewsException('Não foi possível concluir a consulta.');
      cursor = next as String?;
    } while (cursor != null);
    return items;
  }

  Future<ParentAttemptReview> detail(String attemptId) async =>
    ParentAttemptReview.fromJson(await _request('/v1/attempts/$attemptId/review'));

  Future<ParentAttemptReview> save(ReviewChange change) async {
    try {
      final data = await _request('/v1/answers/${change.answerId}/review', method: HttpMethod.put, body: change.toJson());
      return ParentAttemptReview.fromJson(data['detail'] as Map);
    } on PendingReviewsException { rethrow; }
    catch (_) { throw const PendingReviewsException('Não foi possível confirmar a classificação. Consulta o estado ou repete o pedido.', uncertain: true); }
  }

  Future<Map> _request(String path, {HttpMethod method = HttpMethod.get,
    Map<String, dynamic>? query, Map<String, dynamic>? body}) async {
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null) throw const PendingReviewsException('A tua sessão terminou. Entra novamente na conta.', code: 'AUTH_REQUIRED');
      final capability = parentToken();
      if (capability == null) {
        onParentLocked();
        throw const PendingReviewsException('Desbloqueia a área dos pais para continuar.', code: 'PARENT_LOCKED');
      }
      final response = await client.functions.invoke('reviews$path', method: method, queryParameters: query, body: body,
        headers: {'Authorization': 'Bearer ${session.accessToken}', 'X-Parent-Unlock': capability});
      if (response.data is! Map) throw const PendingReviewsException('Não foi possível confirmar o pedido.', uncertain: true);
      return response.data as Map;
    } on PendingReviewsException { rethrow; }
    on FunctionException catch (error) {
      final payload = error.details is Map ? (error.details as Map)['error'] : null;
      final code = payload is Map ? payload['code'] as String? : null;
      if (code == 'PARENT_LOCKED' || code == 'AUTH_REQUIRED' || error.status == 401) onParentLocked();
      throw PendingReviewsException(payload is Map && payload['message'] is String
        ? payload['message'] as String : 'Não foi possível confirmar o pedido de revisão.',
        code: code, uncertain: error.status >= 500);
    } catch (_) {
      throw const PendingReviewsException('Não foi possível ligar ao serviço de revisões. Tenta novamente.', uncertain: true);
    }
  }
}
