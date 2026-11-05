import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/request_id.dart';
import '../../child_session/data/child_session_service.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../domain/attempt_models.dart';
import '../domain/submission_summary.dart';
import 'attempt_service.dart';

class AttemptController extends ChangeNotifier {
  AttemptController({required this.service,required this.assignment,required this.childId});
  final AttemptService service;
  final AssignedWorksheet assignment;
  final String childId;
  AttemptSnapshot? snapshot;
  SubmissionSummary? result;
  bool deliveryPending=false,refreshBeforeSubmit=false,viewLocalDraft=false;
  String? submissionOperation;
  Map<String,int>? submissionRevisions;
  String get submissionKey=>'attempt-submit-$childId-${snapshot!.id}';
  bool get serverSubmitted=>['submitted','pending_review','completed'].contains(snapshot?.status);

  final Map<String,Map<String,dynamic>> values={};
  final Map<String,int> revisions={};
  final Map<String,PendingAnswer> pending={};
  SharedPreferences? preferences;
  int index=0;
  int editGeneration=0;
  bool loading=true,busy=false,diskSaved=false,ready=false;
  int viewVersion=0;
  String? problem,conflictQuestion;
  bool disposed=false;
  Timer? debounce;
  Future<void> writes=Future.value();
  String get key=>'attempt-draft-$childId-${snapshot!.id}';
  AttemptQuestion get question=>snapshot!.questions[index];
  bool get writable=>snapshot?.writable==true&&result==null&&!deliveryPending&&!refreshBeforeSubmit;
  int get answered=>snapshot!.questions.where((q){final a=values[q.id];return a?['mode']=='multiple-choice'||a?['mode']=='paper'||(a?['mode']=='typed'&&(a?['text'] as String? ?? '').trim().isNotEmpty);}).length;
  void emit(){if(!disposed)notifyListeners();}

  Future<void> open() async {
    loading=true;ready=false;problem=null;result=null;deliveryPending=false;refreshBeforeSubmit=false;viewLocalDraft=false;emit();
    try{
      preferences=await SharedPreferences.getInstance();
      if(disposed)return;
      final result=await service.open(assignment,childId,preferences!);
      if(disposed)return;
      if(result.childId!=childId||result.assignmentId!=assignment.id||result.questions.isEmpty)throw const ChildSessionException('Não foi possível abrir esta ficha no teu perfil.');
      snapshot=result;values.clear();revisions.clear();pending.clear();
      for(final entry in result.answers.entries){values[entry.key]=Map.of(entry.value.value);revisions[entry.key]=entry.value.revision;}
      final source=preferences!.getString(key);
      if(source!=null){
        final saved=jsonDecode(source) as Map;
        if(saved['childId']!=childId||saved['attemptId']!=result.id)throw const ChildSessionException('Não foi possível recuperar as alterações deste perfil. Mantém a ficha aberta.');
        final ids=result.questions.map((q)=>q.id).toSet();
        for(final entry in ((saved['pending'] as Map?)??{}).entries){
          if(!ids.contains(entry.key))throw const ChildSessionException('Não foi possível recuperar uma resposta local. Mantém a ficha aberta.');
          final draft=PendingAnswer.fromJson(entry.value as Map);pending[entry.key as String]=draft;values[entry.key as String]=Map.of(draft.answer);
        }
        final cursor=saved['index'];if(cursor is int)index=cursor.clamp(0,result.questions.length-1).toInt();
      }
      final intent=preferences!.getString(submissionKey);
      if(intent!=null){
        final saved=jsonDecode(intent) as Map;
        if(saved['childId']!=childId||saved['attemptId']!=result.id)throw const ChildSessionException('Não foi possível recuperar a confirmação da entrega. Mantém a ficha aberta.');
        submissionOperation=saved['operationId'] as String;
        submissionRevisions=(saved['expectedRevisions'] as Map).map((id,revision)=>MapEntry(id as String,revision as int));
        deliveryPending=true;
      }
      diskSaved=true;ready=true;
      if(serverSubmitted)await loadResult();
    }catch(error){problem=error is ChildSessionException?error.message:'Não foi possível abrir ou recuperar o progresso da ficha.';rethrow;}
    finally{loading=false;emit();}
  }

  void edit(Map<String,dynamic> answer){
    if(!writable||busy||conflictQuestion!=null)return;
    final id=question.id;
    if(jsonEncode(values[id])==jsonEncode(answer))return;
    values[id]=Map.of(answer);
    pending[id]=PendingAnswer(operationId:newRequestId(),baseRevision:pending[id]?.baseRevision??revisions[id]??0,answer:Map.of(answer));
    editGeneration++;diskSaved=false;problem=null;
    debounce?.cancel();debounce=Timer(const Duration(milliseconds:150),(){persist().catchError((Object _){});});emit();
  }

  Future<void> persist() async {
    debounce?.cancel();if(!ready||snapshot==null||preferences==null)return;
    final version=editGeneration;
    final storageKey=key;
    final encoded=jsonEncode({'childId':childId,'attemptId':snapshot!.id,'index':index,
      'pending':pending.map((id,draft)=>MapEntry(id,draft.toJson()))});
    writes=writes.catchError((Object _){}).then((_)async{
      if(!await preferences!.setString(storageKey,encoded))throw const ChildSessionException('Não foi possível guardar as alterações. Mantém a ficha aberta e tenta novamente.');
    });
    try{await writes;if(!disposed&&version==editGeneration)diskSaved=true;}
    catch(_){if(!disposed){diskSaved=false;problem='Não foi possível guardar as alterações. Mantém a ficha aberta.';}rethrow;}
    finally{emit();}
  }

  Future<void> saveAll() async {
    if(busy)return;
    busy=true;problem=null;emit();
    try{
      await persist();
      if(disposed)return;
      if(!writable&&pending.isNotEmpty)throw const ChildSessionException('Esta tentativa já não permite alterar respostas. As alterações locais foram preservadas.');
      for(final q in snapshot!.questions){
        if(disposed)return;
        final draft=pending[q.id];if(draft==null)continue;
        try{
          final revision=await service.save(snapshot!.id,q.id,draft);
          if(disposed)return;
          if((revisions[q.id]??0)>revision)throw const ChildSessionException('Esta resposta foi alterada noutro dispositivo.',code:'ANSWER_REVISION_CONFLICT');
          revisions[q.id]=revision;pending.remove(q.id);editGeneration++;await persist();
        }on ChildSessionException catch(error){
          if(error.code=='ANSWER_REVISION_CONFLICT'){conflictQuestion=q.id;index=snapshot!.questions.indexWhere((item)=>item.id==q.id);}
          rethrow;
        }
      }
    }catch(error){problem=error is ChildSessionException?error.message:'Não foi possível guardar no servidor. As alterações deste dispositivo foram preservadas.';rethrow;}
    finally{busy=false;emit();}
  }

  Future<void> move(int target) async {
    if(target<0||target>=snapshot!.questions.length)return;
    if(result==null&&!serverSubmitted)await saveAll();if(disposed)return;index=target;editGeneration++;await persist();emit();
  }

  Future<void> resolveConflict({required bool keepMine}) async {
    final id=conflictQuestion;if(id==null||busy)return;
    busy=true;problem=null;emit();
    try{
      final remote=await service.get(snapshot!.id);
      if(disposed)return;
      snapshot=remote;
      final saved=remote.answers[id];final mine=pending[id];
      revisions[id]=saved?.revision??0;
      if(keepMine&&mine!=null){
        pending[id]=PendingAnswer(operationId:newRequestId(),baseRevision:revisions[id]!,answer:Map.of(mine.answer));
      }else{pending.remove(id);values[id]=Map.of(saved?.value??{'mode':'unanswered'});}
      conflictQuestion=null;viewVersion++;editGeneration++;await persist();
    }catch(error){problem=error is ChildSessionException?error.message:'Não foi possível consultar a resposta do servidor.';rethrow;}
    finally{busy=false;emit();}
    if(keepMine)await saveAll();
  }

  Future<void> _acceptResult(SubmissionSummary summary) async {
    if(summary.attemptId!=snapshot!.id||summary.childId!=childId||!['submitted','pending_review','completed'].contains(summary.status)) {
      throw const ChildSessionException('Não foi possível confirmar a entrega desta ficha.');
    }
    result=summary;deliveryPending=false;refreshBeforeSubmit=false;viewLocalDraft=false;problem=null;
    submissionOperation=null;submissionRevisions=null;
    try{await preferences!.remove(submissionKey);}catch(_){/* Server confirmation remains authoritative. */}
    emit();
  }

  Future<void> loadResult() async {
    if(busy)return;busy=true;emit();
    try{final summary=await service.result(snapshot!.id);if(!disposed)await _acceptResult(summary);}
    catch(error){problem=error is ChildSessionException?error.message:'Não foi possível consultar a confirmação da entrega.';rethrow;}
    finally{busy=false;emit();}
  }

  Future<void> submit() async {
    if(busy||disposed||result!=null||refreshBeforeSubmit)return;
    if(!deliveryPending){await saveAll();if(disposed)return;}
    busy=true;problem=null;emit();
    try{
      if(!deliveryPending){
        if(pending.isNotEmpty)throw const ChildSessionException('Guarda as respostas antes de entregar.');
        final expected=<String,int>{for(final q in snapshot!.questions)q.id:revisions[q.id]??0};
        final operation=newRequestId();
        final encoded=jsonEncode({'attemptId':snapshot!.id,'childId':childId,'operationId':operation,'expectedRevisions':expected});
        if(!await preferences!.setString(submissionKey,encoded))throw const ChildSessionException('Não foi possível preparar a confirmação. Tenta novamente.');
        submissionOperation=operation;submissionRevisions=expected;deliveryPending=true;emit();
      }
      final summary=await service.submit(snapshot!.id,submissionOperation!,submissionRevisions!);
      if(!disposed)await _acceptResult(summary);
    }catch(error){
      if(error is ChildSessionException&&error.code=='ATTEMPT_REVISION_CONFLICT'){
        deliveryPending=false;submissionOperation=null;submissionRevisions=null;refreshBeforeSubmit=true;
        try{await preferences!.remove(submissionKey);}catch(_){/* Keep drafts even when local cleanup fails. */}
      }
      problem=error is ChildSessionException?error.message:'Ainda não foi possível confirmar a entrega. Tenta novamente.';
      rethrow;
    }finally{busy=false;emit();}
  }

  Future<void> refreshForSubmission() async {
    if(busy)return;
    if(pending.isNotEmpty)throw const ChildSessionException('Existem alterações locais por guardar. Resolve-as antes de atualizar a ficha.');
    busy=true;emit();
    try{
      final remote=await service.get(snapshot!.id);if(disposed)return;
      snapshot=remote;values.clear();revisions.clear();
      for(final entry in remote.answers.entries){values[entry.key]=Map.of(entry.value.value);revisions[entry.key]=entry.value.revision;}
      index=0;viewVersion++;editGeneration++;refreshBeforeSubmit=false;deliveryPending=false;
      problem='Revê as respostas atualizadas antes de confirmar a entrega.';
      await persist();
      if(serverSubmitted){final summary=await service.result(snapshot!.id);if(!disposed)await _acceptResult(summary);}
    }catch(error){problem=error is ChildSessionException?error.message:'Não foi possível atualizar a ficha.';rethrow;}
    finally{busy=false;emit();}
  }

  void showLocalDraft(){viewLocalDraft=true;emit();}
  void showResult(){viewLocalDraft=false;emit();}

  @override void dispose(){
    debounce?.cancel();
    // Best effort on session expiry/unmount. Explicit Pause waits for persistence.
    if(ready&&snapshot!=null&&preferences!=null){persist().catchError((Object _){});}
    disposed=true;super.dispose();
  }
}
