import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../../family/domain/family_models.dart';
import '../data/worksheet_service.dart';
import '../domain/worksheet_models.dart';

class PrepareWorksheetPage extends StatefulWidget {
  const PrepareWorksheetPage({super.key,required this.children,required this.service,required this.onClose,required this.onViewChild});
  final List<ChildProfile> children;
  final WorksheetService service;
  final VoidCallback onClose;
  final Future<void> Function(String) onViewChild;
  @override State<PrepareWorksheetPage> createState()=>_PrepareWorksheetPageState();
}
class _PrepareWorksheetPageState extends State<PrepareWorksheetPage> {
  List<SchoolSubject> subjects=[];
  List<SchoolTopic> topics=[];
  List<WorksheetSummary> proposals=[];
  ChildProfile? child;
  SchoolSubject? subject;
  final selectedTopics=<String>{};
  WorksheetSummary? worksheet;
  Map? detail;
  bool loading=true,busy=false,success=false;
  String? error;
  String requestId='';
  int step=1;
  int generation=0;

  @override void initState(){super.initState();child=widget.children.isEmpty?null:widget.children.first;loadSubjects();}
  Future<void> loadSubjects() async {
    setState((){loading=true;error=null;});
    try{final data=await widget.service.subjects();if(!mounted)return;setState(()=>subjects=data);}
    on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> loadTopics() async {
    final target=subject; final profile=child;if(target==null||profile==null)return;
    final current=++generation;
    setState((){loading=true;topics=[];selectedTopics.clear();error=null;});
    try{final data=await widget.service.topics(target.id,profile.schoolYear);if(mounted&&current==generation)setState(()=>topics=data);}
    on WorksheetException catch(failure){if(mounted&&current==generation)setState(()=>error=failure.message);}
    finally{if(mounted&&current==generation)setState(()=>loading=false);}
  }
  Future<void> propose() async {
    if(busy||child==null||subject==null||selectedTopics.isEmpty)return;
    setState((){busy=true;error=null;});
    try{
      final data=await widget.service.proposals(subject!.id,child!.schoolYear,selectedTopics);
      if(!mounted)return;
      if(data.isEmpty){setState(()=>error='Ainda não existe uma ficha publicada para estes temas. Escolhe outra combinação.');return;}
      final content=await widget.service.detail(data.first);
      if(!mounted)return;
      setState((){proposals=data;worksheet=data.first;detail=content;step=2;requestId=newRequestId();});
    }on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> chooseProposal(WorksheetSummary selected) async {
    if(busy)return;
    setState((){busy=true;error=null;});
    try{final content=await widget.service.detail(selected);if(mounted)setState((){worksheet=selected;detail=content;requestId=newRequestId();});}
    on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> assign() async {
    if(busy||worksheet==null||child==null)return;
    setState((){busy=true;error=null;});
    try{await widget.service.assign(child!.id,worksheet!.versionId,requestId);if(mounted)setState(()=>success=true);}
    on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  void reset()=>setState((){step=1;success=false;worksheet=null;detail=null;proposals=[];error=null;requestId='';});
  Future<void> viewChild() async {
    if(busy||child==null)return;
    setState(()=>busy=true);
    try{await widget.onViewChild(child!.id);}
    catch(_){if(mounted)setState(()=>error='Não foi possível abrir o espaço infantil. Tenta novamente.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget feedback()=>error==null?const SizedBox.shrink():Padding(padding:const EdgeInsets.symmetric(vertical:16),
    child:Semantics(liveRegion:true,child:Text(error!,style:const TextStyle(color:AppColors.error))));
  Widget heading(String value)=>Padding(padding:const EdgeInsets.only(top:24,bottom:14),child:Text(value,style:Theme.of(context).textTheme.titleLarge));

  @override Widget build(BuildContext context){
    if(success)return confirmation();
    if(step==2&&worksheet!=null)return proposalPage();
    return AppPage(title:'Para quem é a ficha hoje?',subtitle:'Escolhe a criança, a disciplina e os temas do ano escolar.',children:[
      const Wrap(children:[AppBadge(label:'Passo 1 de 2 • Preparar ficha',icon:Icons.auto_stories_outlined)]),
      heading('Educando'),
      Wrap(spacing:10,runSpacing:10,children:[for(final profile in widget.children)ChoiceChip(
        label:Text('${profile.displayName} • ${profile.schoolYear}.º Ano'),selected:child?.id==profile.id,
        onSelected:busy||loading?null:(_){setState(()=>child=profile);if(subject!=null)loadTopics();})]),
      heading('Disciplina'),
      if(subjects.isEmpty&&!loading)const Text('O catálogo ainda não tem disciplinas disponíveis.'),
      Wrap(spacing:10,runSpacing:10,children:[for(final item in subjects)ChoiceChip(label:Text(item.name),selected:subject?.id==item.id,
        onSelected:busy||loading?null:(_){setState(()=>subject=item);loadTopics();})]),
      heading('Temas a praticar'),
      if(loading)const Center(child:CircularProgressIndicator(semanticsLabel:'A carregar o catálogo'))
      else if(subject==null)const Text('Escolhe uma disciplina para consultar os temas.')
      else if(topics.isEmpty)const Text('Ainda não existem temas para esta disciplina e ano escolar.')
      else ...[
        Align(alignment:Alignment.centerLeft,child:TextButton(onPressed:busy?null:()=>setState((){
          if(selectedTopics.length==topics.length){selectedTopics.clear();}else{selectedTopics.addAll(topics.map((item)=>item.id));}
        }),child:Text(selectedTopics.length==topics.length?'Limpar seleção':'Selecionar todos'))),
        for(final item in topics)Padding(padding:const EdgeInsets.only(bottom:12),child:AppCard(
          selected:selectedTopics.contains(item.id),padding:const EdgeInsets.all(8),
          child:CheckboxListTile(title:Text(item.name),value:selectedTopics.contains(item.id),
            onChanged:busy?null:(checked)=>setState((){if(checked==true){selectedTopics.add(item.id);}else{selectedTopics.remove(item.id);}})))),
      ],
      feedback(),
      if(error!=null)TextButton(onPressed:busy||loading?null:(){if(subject==null){loadSubjects();}else{loadTopics();}},child:const Text('Atualizar catálogo')),
      const SizedBox(height:24),
      AppButton(label:'Ver proposta de ficha',icon:Icons.arrow_forward_rounded,loading:busy,
        onPressed:busy||loading||child==null||subject==null||selectedTopics.isEmpty?null:propose),
      const SizedBox(height:16),
      AppButton(label:'Voltar à área dos pais',variant:AppButtonVariant.secondary,onPressed:busy?null:widget.onClose),
    ]);
  }

  Widget proposalPage(){
    final item=worksheet!;
    final content=detail?['content'];final rawQuestions=content is Map?content['questions']:null;
    final questions=rawQuestions is List?rawQuestions.whereType<Map>().toList():<Map>[];
    return AppPage(title:'Proposta de ficha preparada',subtitle:'Para ${child!.displayName} • ${item.subjectName} • ${item.schoolYear}.º Ano',children:[
      const Wrap(children:[AppBadge(label:'Passo 2 de 2 • Rever e ajustar',icon:Icons.fact_check_outlined)]),
      const SizedBox(height:24),
      if(proposals.length>1)...[
        for(final candidate in proposals)Padding(padding:const EdgeInsets.only(bottom:12),child:AppCard(
          selected:candidate.versionId==item.versionId,onTap:busy?null:()=>chooseProposal(candidate),
          child:Row(children:[Icon(candidate.versionId==item.versionId?Icons.check_circle_rounded:Icons.circle_outlined,color:AppColors.primary),
            const SizedBox(width:12),Expanded(child:Text(candidate.title))]))),
        const SizedBox(height:16),
      ],
      AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(item.title,style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:18),
        Wrap(spacing:8,runSpacing:8,children:[AppBadge(label:'${item.questionCount} perguntas',icon:Icons.quiz_outlined),
          AppBadge(label:item.sizeLabel),if(item.isSample)const AppBadge(label:'Ficha de exemplo',background:AppColors.amberSoft,color:AppColors.amber)]),
        const SizedBox(height:20),
        Text('${item.choiceCount} perguntas de escolha múltipla'),
        const SizedBox(height:8),Text('${item.writtenCount} perguntas abertas para revisão parental'),
        const SizedBox(height:16),const Text('Sem limite de tempo.'),
        ExpansionTile(title:const Text('Temas abrangidos'),children:[for(final name in item.topicNames)ListTile(title:Text(name))]),
        ExpansionTile(title:const Text('Pré-visualizar perguntas'),children:[for(var i=0;i<questions.length;i++)ListTile(
          leading:Text('${i+1}'),title:Text('${questions[i]['prompt']}'),
          subtitle:Text(questions[i]['type']=='written'?'Resposta aberta':'Escolha múltipla'))]),
      ])),
      feedback(),const SizedBox(height:24),
      AppButton(label:'Disponibilizar ficha a ${child!.displayName}',icon:Icons.rocket_launch_rounded,loading:busy,onPressed:busy?null:assign),
      const SizedBox(height:16),
      AppButton(label:'Voltar e mudar temas',variant:AppButtonVariant.secondary,onPressed:busy?null:reset),
    ]);
  }

  Widget confirmation(){final item=worksheet!;return AppPage(title:'Ficha pronta para ${child!.displayName}!',
    subtitle:'A ficha já está disponível no perfil da criança.',children:[
      AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.check_circle_rounded,color:AppColors.success,size:64),const SizedBox(height:20),
        Text(item.title,textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:16),
        Text('${item.subjectName} • ${item.schoolYear}.º Ano • ${item.questionCount} perguntas',textAlign:TextAlign.center),
        const SizedBox(height:12),Text(item.topicNames.join(' • '),textAlign:TextAlign.center),
        if(item.isSample)...[const SizedBox(height:16),const Center(child:AppBadge(label:'Ficha de exemplo'))],
      ])),feedback(),const SizedBox(height:24),
      AppButton(label:'Ver no perfil de ${child!.displayName}',icon:Icons.person_outline_rounded,loading:busy,onPressed:busy?null:viewChild),
      const SizedBox(height:16),AppButton(label:'Preparar outra ficha',variant:AppButtonVariant.secondary,onPressed:busy?null:reset),
      const SizedBox(height:16),AppButton(label:'Voltar à área dos pais',variant:AppButtonVariant.secondary,onPressed:busy?null:widget.onClose),
    ]);}
}
