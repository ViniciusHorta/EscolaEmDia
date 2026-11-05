import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/request_id.dart';
import '../../child_session/data/child_session_service.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../domain/attempt_models.dart';
import '../domain/submission_summary.dart';
import '../domain/child_feedback_models.dart';

class AttemptService {
  const AttemptService(this.sessions);
  final ChildSessionService sessions;
  Future<AttemptSnapshot> open(AssignedWorksheet assignment,String childId,SharedPreferences preferences,{String? repeatFromAttemptId}) async {
    final knownAttempt=assignment.activeAttemptId??assignment.latestAttemptId;
    if(repeatFromAttemptId==null&&knownAttempt!=null)return get(knownAttempt);
    // Each completed source attempt gets its own durable operation ID. Never reuse the first start key.
    final key=repeatFromAttemptId==null?'attempt-start-$childId-${assignment.id}'
      :'attempt-start-$childId-${assignment.id}-after-$repeatFromAttemptId';
    var requestId=preferences.getString(key);
    if(requestId==null){requestId=newRequestId();if(!await preferences.setString(key,requestId)){
      throw const ChildSessionException('Não foi possível preparar a gravação desta ficha. Tenta novamente.');
    }}
    return AttemptSnapshot.fromJson(await sessions.attemptRequest('/v1/assignments/${assignment.id}/attempts',method:'POST',body:{'clientRequestId':requestId,if(repeatFromAttemptId!=null)'previousAttemptId':repeatFromAttemptId}));
  }
  Future<ChildAttemptFeedback> feedback(String attemptId,String childId) async {
    final data=ChildAttemptFeedback.fromJson(await sessions.attemptRequest('/v1/attempts/$attemptId/feedback'));
    if(data.summary.attemptId!=attemptId||data.summary.childId!=childId||data.summary.status!='completed'||data.questions.isEmpty){
      throw const ChildSessionException('Não foi possível confirmar a correção desta tentativa.');
    }
    return data;
  }
  Future<AttemptSnapshot> get(String id) async=>AttemptSnapshot.fromJson(await sessions.attemptRequest('/v1/attempts/$id'));
  Future<int> save(String attemptId,String questionId,PendingAnswer draft) async {
    final response=await sessions.attemptRequest('/v1/attempts/$attemptId/answers/${Uri.encodeComponent(questionId)}',method:'PUT',body:draft.toJson());
    if(response['syncStatus']!='confirmed'||response['revision'] is! int)throw const ChildSessionException('Não foi possível confirmar a gravação. Tenta novamente.');
    return response['revision'] as int;
  }
  Future<SubmissionSummary> submit(String attemptId,String operationId,Map<String,int> revisions) async {
    final result=await sessions.attemptRequest('/v1/attempts/$attemptId/submit',method:'POST',
      body:{'operationId':operationId,'expectedRevisions':revisions});
    return SubmissionSummary.fromJson(result);
  }
  Future<SubmissionSummary> result(String id) async=>SubmissionSummary.fromJson(
    await sessions.attemptRequest('/v1/attempts/$id/result'));

}
