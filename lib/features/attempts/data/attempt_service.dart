import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/request_id.dart';
import '../../child_session/data/child_session_service.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../domain/attempt_models.dart';

class AttemptService {
  const AttemptService(this.sessions);
  final ChildSessionService sessions;
  Future<AttemptSnapshot> open(AssignedWorksheet assignment,String childId,SharedPreferences preferences) async {
    if(assignment.activeAttemptId!=null)return get(assignment.activeAttemptId!);
    final key='attempt-start-$childId-${assignment.id}';
    var requestId=preferences.getString(key);
    if(requestId==null){requestId=newRequestId();if(!await preferences.setString(key,requestId)){
      throw const ChildSessionException('Não foi possível preparar a gravação desta ficha. Tenta novamente.');
    }}
    return AttemptSnapshot.fromJson(await sessions.attemptRequest('/v1/assignments/${assignment.id}/attempts',method:'POST',body:{'clientRequestId':requestId}));
  }
  Future<AttemptSnapshot> get(String id) async=>AttemptSnapshot.fromJson(await sessions.attemptRequest('/v1/attempts/$id'));
  Future<int> save(String attemptId,String questionId,PendingAnswer draft) async {
    final response=await sessions.attemptRequest('/v1/attempts/$attemptId/answers/${Uri.encodeComponent(questionId)}',method:'PUT',body:draft.toJson());
    if(response['syncStatus']!='confirmed'||response['revision'] is! int)throw const ChildSessionException('Não foi possível confirmar a gravação. Tenta novamente.');
    return response['revision'] as int;
  }
}
