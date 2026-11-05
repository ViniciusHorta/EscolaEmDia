import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../child_session/data/child_session_service.dart';
import '../../worksheets/domain/worksheet_models.dart';
import '../data/attempt_controller.dart';
import '../data/attempt_service.dart';
import 'widgets/attempt_chrome.dart';
import 'widgets/question_answer_editor.dart';
import 'submission_summary_page.dart';
import 'child_feedback_page.dart';

class WorksheetAttemptPage extends StatefulWidget {
  const WorksheetAttemptPage({super.key,required this.assignment,required this.childId,required this.sessions,
    required this.onPause,required this.onExpired,required this.onOpenParents,required this.onRepeat,this.repeatFromAttemptId,this.childName,this.childEmoji});
  final AssignedWorksheet assignment;
  final String childId;
  final String? repeatFromAttemptId;
  final String? childName,childEmoji;
  final ValueChanged<String> onRepeat;
  final ChildSessionService sessions;
  final VoidCallback onPause,onExpired,onOpenParents;
  @override State<WorksheetAttemptPage> createState()=>_WorksheetAttemptPageState();
}
class _WorksheetAttemptPageState extends State<WorksheetAttemptPage> {
  late final AttemptController controller;
  bool confirmingDelivery=false;
  bool showingFeedback=false;
  @override void initState(){super.initState();controller=AttemptController(service:AttemptService(widget.sessions),assignment:widget.assignment,childId:widget.childId,repeatFromAttemptId:widget.repeatFromAttemptId);open();}
  Future<void> open()async{try{await controller.open();}on ChildSessionException catch(error){if(error.ended&&mounted)widget.onExpired();}catch(_){/* Message is held by the controller. */}}
  @override void dispose(){controller.dispose();super.dispose();}
  Future<void> run(Future<void> Function() action)async{
    if(controller.busy)return;
    try{await action();}
    on ChildSessionException catch(error){if(error.ended&&mounted)widget.onExpired();}
    catch(_){/* Preserve local changes; controller displays the failure. */}
  }
  Future<void> pause()async{
    await run(()async{await controller.saveAll();if(mounted)widget.onPause();});
  }
  Future<void> pauseLocally()async{
    await run(()async{await controller.persist();if(mounted)widget.onPause();});
  }
  Future<void> parents()async{
    await run(()async{await controller.persist();if(mounted)widget.onOpenParents();});
  }
  Future<void> finish()async{
    await run(()async{await controller.saveAll();if(mounted)setState(()=>confirmingDelivery=true);});
  }
  Future<void> repeat()async{
    final result=controller.result;
    if(result==null||result.status!='completed')return;
    await run(()async{await controller.persist();if(mounted)widget.onRepeat(result.attemptId);});
  }
  Future<void> closeSummary()async{
    await run(()async{await controller.persist();if(mounted)widget.onPause();});
  }
  Widget confirmation()=>AppPage(
    title:controller.deliveryPending?'A confirmar a entrega':'Tudo pronto para entregar?',
    subtitle:controller.deliveryPending?'A entrega ainda não foi confirmada pelo servidor.':'Confere o resumo antes de entregar a ficha.',
    children:[
      AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(controller.snapshot!.title,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:16),
        Text('${controller.answered} de ${controller.snapshot!.questions.length} perguntas respondidas.'),
        if(controller.answered<controller.snapshot!.questions.length)...[
          const SizedBox(height:12),const Text('Há perguntas sem resposta. Podes voltar à ficha ou confirmar a entrega assim.'),
        ],
        const SizedBox(height:16),const Text('Depois da confirmação, esta tentativa deixa de permitir alterações.'),
      ])),
      if(controller.problem!=null)...[const SizedBox(height:20),Semantics(liveRegion:true,child:Text(controller.problem!))],
      const SizedBox(height:24),
      if(controller.refreshBeforeSubmit)
        AppButton(label:'Rever alterações do servidor',onPressed:controller.busy?null:()=>run(()async{
          await controller.refreshForSubmission();if(mounted)setState(()=>confirmingDelivery=false);
        }))
      else AppButton(label:controller.deliveryPending?'Tentar confirmar entrega':'Confirmar entrega',icon:Icons.cloud_done_outlined,
        loading:controller.busy,onPressed:controller.busy?null:()=>run(controller.submit)),
      if(!controller.deliveryPending)...[
        const SizedBox(height:16),AppButton(label:'Voltar à ficha',variant:AppButtonVariant.secondary,
          onPressed:controller.busy?null:()=>setState(()=>confirmingDelivery=false)),
      ],
      const SizedBox(height:16),AppButton(label:'Voltar ao meu espaço',variant:AppButtonVariant.secondary,onPressed:controller.busy?null:closeSummary),
      if(controller.deliveryPending)...[
        const SizedBox(height:12),TextButton(onPressed:controller.busy?null:()=>run(controller.loadResult),child:const Text('Consultar estado da entrega')),
      ],
    ],
  );

  @override Widget build(BuildContext context)=>PopScope(canPop:false,child:ListenableBuilder(listenable:controller,builder:(context,_){
    if(controller.loading)return const Scaffold(body:Center(child:CircularProgressIndicator(semanticsLabel:'A abrir a tua ficha')));
    if(!controller.ready)return AppPage(title:'Vamos tentar outra vez?',subtitle:controller.problem??'Não foi possível abrir a ficha.',children:[
      AppButton(label:'Tentar novamente',onPressed:open),const SizedBox(height:16),
      AppButton(label:'Voltar ao meu espaço',variant:AppButtonVariant.secondary,onPressed:widget.onPause),
    ]);
    if(showingFeedback&&controller.result?.status=='completed')return ChildFeedbackPage(
      key:ValueKey(controller.result!.attemptId),attemptId:controller.result!.attemptId,childId:widget.childId,
      service:controller.service,onClose:()=>setState((){showingFeedback=false;}),onParents:parents,onExpired:widget.onExpired,
    );
    if(controller.result!=null&&!controller.viewLocalDraft)return SubmissionSummaryPage(summary:controller.result!,
      onViewFeedback:controller.result!.status=='completed'?()=>setState((){showingFeedback=true;}):null,
      loadingResult:controller.busy,onRefreshResult:controller.busy?null:()=>run(controller.loadResult),
      errorMessage:controller.problem,childName:widget.childName,childEmoji:widget.childEmoji,onClose:closeSummary,onParents:parents,onRepeat:controller.result!.status=='completed'?repeat:null,onViewLocalDraft:controller.pending.isEmpty?null:controller.showLocalDraft);
    if(controller.serverSubmitted&&controller.result==null)return AppPage(title:'Consultar entrega',
      subtitle:controller.problem??'Vamos carregar o resumo da tua ficha.',children:[
        AppButton(label:'Consultar resumo',loading:controller.busy,onPressed:controller.busy?null:()=>run(controller.loadResult)),
        const SizedBox(height:16),AppButton(label:'Voltar ao meu espaço',variant:AppButtonVariant.secondary,onPressed:controller.busy?null:closeSummary),
      ]);
    if(controller.result==null&&(controller.deliveryPending||confirmingDelivery))return confirmation();
    final data=controller.snapshot!; final q=controller.question;
    final enabled=!controller.busy&&controller.writable&&controller.conflictQuestion==null;
    final total=data.questions.length;
    final last=controller.index==total-1;
    final blocked=controller.busy||controller.conflictQuestion!=null;
    final gutter=MediaQuery.sizeOf(context).width<640?16.0:32.0;
    return Scaffold(
      backgroundColor:AppColors.background,
      body:Column(children:[
        AttemptTopBar(
          title:'Pergunta ${controller.index+1} de $total',
          subtitle:data.subjectName,
          leading:RoundActionButton(icon:Icons.pause_rounded,tooltip:'Pausar',
            onPressed:controller.busy?null:(controller.result!=null?closeSummary:pause)),
          trailing:RoundActionButton(icon:Icons.lock_outline_rounded,tooltip:'Área dos pais',filled:true,
            onPressed:controller.busy?null:parents),
        ),
        Expanded(child:SingleChildScrollView(
          key:ValueKey('question-${q.id}'),
          keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
          child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),child:Padding(
            padding:EdgeInsets.fromLTRB(gutter,18,gutter,24),
            child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              SegmentedProgress(current:controller.index,answered:[for(final question in data.questions)_isAnswered(controller.values[question.id])]),
              const SizedBox(height:10),
              Row(children:[
                Icon(controller.pending.isEmpty?Icons.cloud_done_outlined:Icons.save_outlined,size:18,color:AppColors.muted),
                const SizedBox(width:6),
                Expanded(child:Text(controller.busy?'A guardar…':controller.pending.isEmpty?'Progresso guardado':controller.diskSaved?'Alterações guardadas neste dispositivo':'A guardar neste dispositivo…',
                  style:const TextStyle(color:AppColors.muted,fontSize:13,fontWeight:FontWeight.w600))),
                if(data.attemptNumber>1)AppBadge(label:'Tentativa ${data.attemptNumber}',icon:Icons.history_rounded),
              ]),
              if(controller.resumedExistingRepeat)...[
                const SizedBox(height:16),
                const AppCard(child:Text('Esta tentativa já tinha progresso guardado. Vamos continuar a partir daí.')),
              ],
              if(!controller.writable)...[
                const SizedBox(height:16),
                const AppCard(color:AppColors.softBlue,child:Text('Esta tentativa está apenas disponível para consulta.')),
              ],
              const SizedBox(height:20),
              AppCard(padding:const EdgeInsets.all(28),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                if(controller.index==0&&data.instructions.isNotEmpty)...[
                  Text(data.instructions,style:const TextStyle(color:AppColors.muted,fontSize:16,height:1.45)),
                  const SizedBox(height:14),
                ],
                HighlightedPrompt(q.prompt,fontSize:q.type=='multiple-choice'?26:22),
                if(data.text.isNotEmpty)...[
                  const SizedBox(height:12),
                  Theme(data:Theme.of(context).copyWith(dividerColor:Colors.transparent),child:ExpansionTile(
                    tilePadding:EdgeInsets.zero,
                    leading:const Icon(Icons.auto_stories_rounded,color:AppColors.primary),
                    title:const Text('Ler o texto',style:TextStyle(fontWeight:FontWeight.w700,color:AppColors.primary)),
                    children:[Padding(padding:const EdgeInsets.only(bottom:8),child:Text(data.text,style:const TextStyle(fontSize:16,height:1.5)))])),
                ],
              ])),
              const SizedBox(height:24),
              QuestionAnswerEditor(key:ValueKey('${data.id}-${q.id}-${controller.viewVersion}'),question:q,value:controller.values[q.id]??{'mode':'unanswered'},enabled:enabled,onChanged:controller.edit),
              if(controller.problem!=null)...[
                const SizedBox(height:20),Semantics(liveRegion:true,child:AppCard(color:AppColors.softBlue,child:Text(controller.problem!))),
                const SizedBox(height:12),
                if(controller.conflictQuestion!=null)...[
                  AppButton(label:'Manter a minha resposta',onPressed:controller.busy?null:()=>run(()=>controller.resolveConflict(keepMine:true))),
                  const SizedBox(height:12),AppButton(label:'Usar resposta do servidor',variant:AppButtonVariant.secondary,onPressed:controller.busy?null:()=>run(()=>controller.resolveConflict(keepMine:false))),
                ]else AppButton(label:'Tentar guardar novamente',onPressed:controller.busy?null:()=>run(controller.saveAll)),
                if(controller.pending.isNotEmpty&&controller.diskSaved)...[
                  const SizedBox(height:12),AppButton(label:'Pausar com alterações neste dispositivo',variant:AppButtonVariant.secondary,onPressed:controller.busy?null:pauseLocally),
                ],
              ],
            ]),
          ))),
        )),
        _BottomNavigation(children:[
          if(controller.index>0)Expanded(child:AppButton(label:'Anterior',variant:AppButtonVariant.neutral,icon:Icons.arrow_back_rounded,
            onPressed:blocked?null:()=>run(()=>controller.move(controller.index-1)))),
          if(controller.index>0)const SizedBox(width:14),
          Expanded(flex:controller.index>0?1:2,child:!last
            ?AppButton(label:controller.index==total-2?'Última pergunta':'Seguinte',icon:Icons.arrow_forward_rounded,loading:controller.busy,
              onPressed:blocked?null:()=>run(()=>controller.move(controller.index+1)))
            :controller.result!=null
              ?AppButton(label:'Ver resumo',icon:Icons.arrow_forward_rounded,onPressed:controller.busy?null:controller.showResult)
              :AppButton(label:'Terminar ficha',icon:Icons.cloud_upload_outlined,variant:AppButtonVariant.success,loading:controller.busy,
                onPressed:blocked||!controller.writable?null:finish)),
        ]),
      ]),
    );
  }));
}

bool _isAnswered(Map<String,dynamic>? value)=>value?['mode']=='multiple-choice'||value?['mode']=='paper'
  ||(value?['mode']=='typed'&&(value?['text'] as String? ?? '').trim().isNotEmpty);

/// Barra fixa inferior com «Anterior» e «Seguinte», acima da área segura.
class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.children});
  final List<Widget> children;
  @override Widget build(BuildContext context)=>Container(
    decoration:BoxDecoration(color:AppColors.background,border:const Border(top:BorderSide(color:AppColors.lavender)),
      boxShadow:[BoxShadow(color:AppColors.primary.withValues(alpha:0.05),blurRadius:14,offset:const Offset(0,-6))]),
    child:SafeArea(top:false,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),
      child:Padding(padding:const EdgeInsets.fromLTRB(16,14,16,8),child:Row(children:children))))),
  );
}
