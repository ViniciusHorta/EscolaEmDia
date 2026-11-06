import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/worksheet_models.dart';

class WorksheetException implements Exception {
  const WorksheetException(this.message);
  final String message;
}
class WorksheetService {
  const WorksheetService(this.client,{required this.parentToken,required this.onParentLocked});
  final SupabaseClient client;
  final String? Function() parentToken;
  final void Function() onParentLocked;

  Future<List<SchoolSubject>> subjects() async => (await _list('/v1/subjects')).map(SchoolSubject.fromJson).toList();
  Future<List<SchoolTopic>> topics(String subjectId,int year) async =>
      (await _list('/v1/topics',{'subjectId':subjectId,'schoolYear':'$year'})).map(SchoolTopic.fromJson).toList();
  Future<List<WorksheetSummary>> proposals(String subjectId,int year,Set<String> topicIds) async =>
      (await _list('/v1/worksheets',{'subjectId':subjectId,'schoolYear':'$year','topicIds':topicIds.join(',')})).map(WorksheetSummary.fromJson).toList();
  Future<Map> detail(WorksheetSummary worksheet) => _request('/v1/worksheets/${worksheet.id}',query:{'versionId':worksheet.versionId});
  Future<void> assign(String childId,String versionId,String requestId) async {
    final result=await _request('/v1/children/$childId/assignments',method:HttpMethod.post,
      body:{'worksheetVersionId':versionId,'clientRequestId':requestId});
    if(result['childId']!=childId || result['worksheetVersionId']!=versionId || result['status']!='active') {
      throw const WorksheetException('Não foi possível confirmar a disponibilização da ficha. Tenta novamente.');
    }
  }
  Future<List<Map>> _list(String path,[Map<String,dynamic>? filters]) async {
    final items=<Map>[];String? cursor;final seen=<String>{};
    do {
      final result=await _request(path,query:{...?filters,if(cursor!=null)'cursor':cursor});
      final page=result['items'];
      if(page is! List || page.any((item)=>item is! Map))throw const WorksheetException('Não foi possível ler o catálogo.');
      items.addAll(page.cast<Map>());
      final next=result['nextCursor'];
      if(next!=null && (next is! String || !seen.add(next)))throw const WorksheetException('Não foi possível concluir a consulta.');
      cursor=next as String?;
    }while(cursor!=null);
    return items;
  }
  Future<Map> _request(String path,{HttpMethod method=HttpMethod.get,Map<String,dynamic>? query,Map<String,dynamic>? body}) async {
    try {
      var session=client.auth.currentSession;
      if(session?.isExpired==true)session=(await client.auth.refreshSession()).session;
      if(session==null)throw const WorksheetException('A tua sessão terminou. Entra novamente na conta.');
      final capability=parentToken();
      if(capability==null){onParentLocked();throw const WorksheetException('Desbloqueia a área do responsável para continuar.');}
      final response=await client.functions.invoke('worksheets$path',method:method,queryParameters:query,body:body,
        headers:{'Authorization':'Bearer ${session.accessToken}','X-Parent-Unlock':capability});
      if(response.data is! Map)throw const WorksheetException('Não foi possível confirmar o pedido.');
      return response.data as Map;
    }on WorksheetException{rethrow;}
    on FunctionException catch(error){
      final data=error.details;final payload=data is Map?data['error']:null;
      if(payload is Map && payload['code']=='PARENT_LOCKED')onParentLocked();
      throw WorksheetException(payload is Map && payload['message'] is String?payload['message'] as String:'Não foi possível aceder às fichas.');
    }catch(_){throw const WorksheetException('Não foi possível ligar ao serviço. Tenta novamente.');}
  }
}
