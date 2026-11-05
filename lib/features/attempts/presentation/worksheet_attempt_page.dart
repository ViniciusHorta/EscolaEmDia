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
import 'widgets/question_answer_editor.dart';

class WorksheetAttemptPage extends StatefulWidget {
  const WorksheetAttemptPage({super.key,required this.assignment,required this.childId,required this.sessions,
    required this.onPause,required this.onExpired,required this.onOpenParents});
  final AssignedWorksheet assignment;
  final String childId;
  final ChildSessionService sessions;
  final VoidCallback onPause,onExpired,onOpenParents;
  @override State<WorksheetAttemptPage> createState()=>_WorksheetAttemptPageState();
}
class _WorksheetAttemptPageState extends State<WorksheetAttemptPage> {
  late final AttemptController controller;
  @override void initState(){super.initState();controller=AttemptController(service:AttemptService(widget.sessions),assignment:widget.assignment,childId:widget.childId);open();}
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
  @override Widget build(BuildContext context)=>PopScope(canPop:false,child:ListenableBuilder(listenable:controller,builder:(context,_){
    if(controller.loading)return const Scaffold(body:Center(child:CircularProgressIndicator(semanticsLabel:'A abrir a tua ficha')));
    if(!controller.ready)return AppPage(title:'Vamos tentar outra vez?',subtitle:controller.problem??'Não foi possível abrir a ficha.',children:[
      AppButton(label:'Tentar novamente',onPressed:open),const SizedBox(height:16),
      AppButton(label:'Voltar ao meu espaço',variant:AppButtonVariant.secondary,onPressed:widget.onPause),
    ]);
    final data=controller.snapshot!; final q=controller.question;
    final enabled=!controller.busy&&controller.writable&&controller.conflictQuestion==null;
    return AppPage(title:'Pergunta ${controller.index+1} de ${data.questions.length}',subtitle:'${data.subjectName} • Sem pressa, com calma',children:[
      Row(children:[Expanded(child:Text(data.title,style:Theme.of(context).textTheme.titleMedium)),
        const SizedBox(width:12),TextButton.icon(onPressed:controller.busy?null:pause,icon:const Icon(Icons.pause_circle_outline_rounded),label:const Text('Pausar'))]),
      const SizedBox(height:18),
      Semantics(label:'${controller.answered} de ${data.questions.length} perguntas respondidas',child:LinearProgressIndicator(
        value:controller.answered/data.questions.length,minHeight:10,borderRadius:BorderRadius.circular(20))),
      const SizedBox(height:16),
      Wrap(spacing:8,runSpacing:8,children:[AppBadge(label:'${controller.answered} respondidas'),
        AppBadge(label:controller.busy?'A guardar…':controller.pending.isEmpty?'Progresso guardado':controller.diskSaved?'Alterações guardadas neste dispositivo':'A guardar neste dispositivo…',icon:Icons.save_outlined)]),
      if(!controller.writable)...[const SizedBox(height:20),const Text('Esta tentativa está apenas disponível para consulta.')],
      if(data.instructions.isNotEmpty)...[const SizedBox(height:20),Text(data.instructions)],
      if(data.text.isNotEmpty)...[const SizedBox(height:16),ExpansionTile(title:const Text('Ler o texto'),children:[Padding(padding:const EdgeInsets.all(16),child:Text(data.text))])],
      const SizedBox(height:28),
      Text(q.prompt,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:24),
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
      const SizedBox(height:28),
      if(controller.index>0)...[
        AppButton(label:'Anterior',variant:AppButtonVariant.secondary,icon:Icons.arrow_back_rounded,
          onPressed:controller.busy||controller.conflictQuestion!=null?null:()=>run(()=>controller.move(controller.index-1))),const SizedBox(height:14),
      ],
      if(controller.index<data.questions.length-1)
        AppButton(label:'Seguinte',icon:Icons.arrow_forward_rounded,loading:controller.busy,
          onPressed:controller.busy||controller.conflictQuestion!=null?null:()=>run(()=>controller.move(controller.index+1)))
      else AppButton(label:'Guardar e pausar',icon:Icons.save_outlined,loading:controller.busy,onPressed:controller.busy||controller.conflictQuestion!=null?null:pause),
      const SizedBox(height:16),TextButton.icon(onPressed:controller.busy?null:parents,icon:const Icon(Icons.lock_outline_rounded),label:const Text('Área dos pais')),
    ]);
  }));
}
