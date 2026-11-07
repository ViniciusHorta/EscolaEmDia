import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../core/utils/search_text.dart';
import '../../../core/utils/subject_icons.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
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
  /// Fichas publicadas da disciplina e do ano, para pesquisar temas também pelo nome das fichas.
  List<WorksheetSummary> catalogue=[];
  final topicSearch=TextEditingController();
  final worksheetSearch=TextEditingController();
  ChildProfile? child;
  SchoolSubject? subject;
  final selectedTopics=<String>{};
  WorksheetSummary? worksheet;
  Map? detail;
  bool loading=true,busy=false,success=false;
  String? error;
  String requestId='';
  /// Onde a criança responde às perguntas abertas: 'typed' (na app) ou 'paper' (no caderno).
  String writtenAnswerMode='typed';
  int step=1;
  int generation=0;

  @override void initState(){super.initState();child=widget.children.isEmpty?null:widget.children.first;loadSubjects();}
  @override void dispose(){topicSearch.dispose();worksheetSearch.dispose();super.dispose();}
  Future<void> loadSubjects() async {
    setState((){loading=true;error=null;});
    try{final data=await widget.service.subjects();if(!mounted)return;setState(()=>subjects=data);}
    on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> loadTopics() async {
    final target=subject; final profile=child;if(target==null||profile==null)return;
    final current=++generation;
    setState((){loading=true;topics=[];catalogue=[];selectedTopics.clear();error=null;});
    try{
      // Sem temas, o catálogo devolve todas as fichas publicadas da disciplina e do ano.
      // Se falhar, a pesquisa continua a funcionar só pelo nome dos temas.
      final fetched=await Future.wait([widget.service.topics(target.id,profile.schoolYear),
        widget.service.proposals(target.id,profile.schoolYear,const <String>{}).catchError((Object _)=>const <WorksheetSummary>[])]);
      if(mounted&&current==generation)setState((){topics=fetched[0] as List<SchoolTopic>;catalogue=fetched[1] as List<WorksheetSummary>;});
    }
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
      // O termo pesquisado nos temas passa para a seleção da ficha e escolhe a primeira que corresponde.
      final term=topicSearch.text.trim();
      final initial=data.firstWhere((item)=>worksheetMatches(item,term),orElse:()=>data.first);
      final content=await widget.service.detail(initial);
      if(!mounted)return;
      worksheetSearch.text=term;
      setState((){proposals=data;worksheet=initial;detail=content;step=2;requestId=newRequestId();});
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
    try{
      await widget.service.assign(child!.id,worksheet!.versionId,requestId,
        writtenAnswerMode:worksheet!.writtenCount>0?writtenAnswerMode:'typed');
      if(mounted)setState(()=>success=true);
    }
    on WorksheetException catch(failure){if(mounted)setState(()=>error=failure.message);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  bool worksheetMatches(WorksheetSummary item,String query)=>
    matchesSearch('${item.title} ${item.topicNames.join(' ')}',query);
  /// Fichas cujo título corresponde à pesquisa e que cobrem este tema.
  List<WorksheetSummary> worksheetHits(SchoolTopic topic,String query)=>normalizeSearch(query).isEmpty?const []
    :catalogue.where((item)=>item.topicNames.contains(topic.name)&&matchesSearch(item.title,query)).toList();
  List<SchoolTopic> get visibleTopics{
    final query=topicSearch.text;
    if(normalizeSearch(query).isEmpty)return topics;
    return topics.where((item)=>selectedTopics.contains(item.id)||matchesSearch(item.name,query)||worksheetHits(item,query).isNotEmpty).toList();
  }

  Widget searchField(TextEditingController controller,String hint)=>TextField(
    controller:controller,
    enabled:!busy,
    textInputAction:TextInputAction.search,
    onChanged:(_)=>setState((){}),
    decoration:InputDecoration(
      hintText:hint,
      prefixIcon:const Icon(Icons.search_rounded),
      suffixIcon:controller.text.isEmpty?null:IconButton(tooltip:'Limpar pesquisa',icon:const Icon(Icons.close_rounded),
        onPressed:()=>setState(controller.clear)),
      filled:true,fillColor:AppColors.softBlue,
      contentPadding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(AppRadii.pill),borderSide:BorderSide.none),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(AppRadii.pill),
        borderSide:const BorderSide(color:AppColors.primary,width:2)),
    ),
  );

  void reset()=>setState((){step=1;success=false;worksheet=null;detail=null;proposals=[];error=null;requestId='';writtenAnswerMode='typed';});
  Future<void> viewChild() async {
    if(busy||child==null)return;
    setState(()=>busy=true);
    try{await widget.onViewChild(child!.id);}
    catch(_){if(mounted)setState(()=>error='Não foi possível abrir o espaço infantil. Tenta novamente.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Widget feedback()=>error==null?const SizedBox.shrink():Padding(padding:const EdgeInsets.only(top:16),
    child:Semantics(liveRegion:true,child:Container(padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(color:AppColors.coralSoft,borderRadius:BorderRadius.circular(20)),
      child:Text(error!,style:const TextStyle(color:AppColors.text)))));

  /// Estimativa simples: escolha múltipla 1,5–2 min; resposta aberta 3–4 min.
  String duration(WorksheetSummary item){
    final low=(item.choiceCount*1.5+item.writtenCount*3).round();
    final high=(item.choiceCount*2+item.writtenCount*4).round();
    return low==high?'~$low minutos':'~$low a $high minutos';
  }

  void showHelp()=>showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
    icon:const Icon(Icons.help_outline_rounded,color:AppColors.primary,size:36),
    title:const Text('Como funciona?'),
    content:const Text('1. Escolhe a criança, a disciplina e os temas.\n'
      '2. Propomos uma ficha publicada que cobre esses temas, já equilibrada entre escolha múltipla e respostas abertas.\n'
      '3. Disponibiliza-a: aparece no espaço da criança. As respostas abertas chegam ao Painel do Responsável para revisão.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Percebi'))],
  ));

  Widget shell({required Widget body,required VoidCallback? onBack,String? title})=>Scaffold(
    backgroundColor:AppColors.background,
    body:Column(children:[
      Container(
        decoration:BoxDecoration(color:AppColors.background,boxShadow:[
          BoxShadow(color:AppColors.primary.withValues(alpha:0.05),blurRadius:14,offset:const Offset(0,6))]),
        child:SafeArea(bottom:false,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),
          child:Padding(padding:const EdgeInsets.fromLTRB(8,6,16,8),child:Row(children:[
            IconButton(onPressed:onBack,tooltip:'Voltar',iconSize:28,icon:const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width:4),
            Expanded(child:title==null?const SizedBox.shrink():Semantics(header:true,child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:21,fontWeight:FontWeight.w700,color:AppColors.text)))),
            IconButton.filledTonal(onPressed:showHelp,tooltip:'Ajuda',
              style:IconButton.styleFrom(backgroundColor:AppColors.lavender,minimumSize:const Size(48,48)),
              icon:const Icon(Icons.help_outline_rounded,color:AppColors.primary)),
          ])))))),
      Expanded(child:SingleChildScrollView(key:ValueKey('step-$step-$success'),child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:720),
        child:Padding(padding:EdgeInsets.fromLTRB(gutter,16,gutter,32),child:body))))),
    ]),
  );
  double get gutter=>MediaQuery.sizeOf(context).width<640?16:32;

  Widget stepHeader(int current,String label)=>Row(children:[
    CircleAvatar(radius:15,backgroundColor:AppColors.primary,
      child:Text('$current',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800,fontSize:14))),
    const SizedBox(width:10),
    Expanded(child:Text('Passo $current de 2 • $label',style:const TextStyle(color:AppColors.primary,fontWeight:FontWeight.w700,fontSize:15))),
    for(var i=1;i<=2;i++)Container(width:i==current?30:22,height:8,margin:const EdgeInsets.only(left:5),
      decoration:BoxDecoration(color:i<=current?AppColors.primary:AppColors.blueBorder,borderRadius:BorderRadius.circular(AppRadii.pill))),
  ]);

  Widget sectionTitle(String text,{Widget? trailing})=>Padding(padding:const EdgeInsets.only(top:28,bottom:12),child:Row(children:[
    Expanded(child:Semantics(header:true,child:Text(text,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)))),
    if(trailing!=null)trailing,
  ]));

  @override Widget build(BuildContext context){
    if(success)return confirmation();
    if(step==2&&worksheet!=null)return proposalPage();
    final ready=!busy&&!loading&&child!=null&&subject!=null&&selectedTopics.isNotEmpty;
    return shell(onBack:busy?null:widget.onClose,body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      stepHeader(1,'Configuração Rápida'),
      const SizedBox(height:20),
      const Text('Para quem é a ficha hoje?',style:TextStyle(fontSize:28,height:1.2,fontWeight:FontWeight.w800,color:AppColors.text)),
      const SizedBox(height:8),
      const Text('Escolhe a disciplina e os temas do ano escolar para gerar uma proposta equilibrada e divertida.',
        style:TextStyle(fontSize:16,height:1.45,color:AppColors.muted)),
      sectionTitle('Educando'),
      SingleChildScrollView(scrollDirection:Axis.horizontal,clipBehavior:Clip.none,child:Row(children:[
        for(final profile in widget.children)Padding(padding:const EdgeInsets.only(right:12),child:_ChildOption(
          child:profile,selected:child?.id==profile.id,
          onTap:busy||loading?null:(){if(child?.id==profile.id)return;setState(()=>child=profile);if(subject!=null)loadTopics();})),
      ])),
      sectionTitle('Disciplina principal',trailing:const AppBadge(label:'Obrigatório',background:AppColors.amberSoft,color:AppColors.amber)),
      if(subjects.isEmpty&&!loading)const Text('O catálogo ainda não tem disciplinas disponíveis.'),
      LayoutBuilder(builder:(context,constraints){
        final columns=constraints.maxWidth>=560?3:2;
        final width=(constraints.maxWidth-14*(columns-1))/columns;
        return Wrap(spacing:14,runSpacing:14,children:[for(final item in subjects)SizedBox(width:width,child:_SubjectOption(
          subject:item,year:child?.schoolYear,selected:subject?.id==item.id,
          topicCount:subject?.id==item.id&&!loading?topics.length:null,
          onTap:busy||loading?null:(){if(subject?.id==item.id)return;setState(()=>subject=item);loadTopics();}))]);
      }),
      const SizedBox(height:20),
      AppCard(padding:const EdgeInsets.fromLTRB(16,20,16,16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Row(children:[
          const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Temas a praticar',style:TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)),
            SizedBox(height:2),
            Text('Seleciona 1 ou mais do currículo oficial',style:TextStyle(fontSize:14,color:AppColors.muted)),
          ])),
          if(visibleTopics.isNotEmpty&&!loading)Builder(builder:(context){
            final visible=visibleTopics.map((item)=>item.id).toList();
            final all=visible.every(selectedTopics.contains);
            return TextButton(
              onPressed:busy?null:()=>setState((){if(all){selectedTopics.removeAll(visible);}else{selectedTopics.addAll(visible);}}),
              style:TextButton.styleFrom(backgroundColor:AppColors.lavender,shape:const StadiumBorder()),
              child:Text(all?'Nenhum':'Todos'));
          }),
        ])),
        const SizedBox(height:16),
        if(loading)const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator(semanticsLabel:'A carregar o catálogo')))
        else if(subject==null)const _HintBox('Escolhe uma disciplina para ver os temas.')
        else if(topics.isEmpty)const _HintBox('Ainda não existem temas para esta disciplina e ano escolar.')
        else ...[
          Padding(padding:const EdgeInsets.only(bottom:14),
            child:searchField(topicSearch,'Pesquisar tema ou nome de ficha')),
          if(visibleTopics.isEmpty)_HintBox('Nenhum tema ou ficha encontrado para «${topicSearch.text.trim()}».'),
        ],
        if(!loading&&subject!=null)for(final item in visibleTopics)Padding(padding:const EdgeInsets.only(bottom:10),child:_TopicOption(
          topic:item,selected:selectedTopics.contains(item.id),
          worksheets:worksheetHits(item,topicSearch.text).map((w)=>w.title).toList(),
          onTap:busy?null:()=>setState((){if(!selectedTopics.remove(item.id))selectedTopics.add(item.id);}))),
        const SizedBox(height:6),
        Container(padding:const EdgeInsets.all(16),
          decoration:BoxDecoration(color:AppColors.lavender,borderRadius:BorderRadius.circular(20)),
          child:Text.rich(TextSpan(style:const TextStyle(fontSize:14,height:1.45,color:AppColors.text),children:[
            const TextSpan(text:'Proposta automática: ',style:TextStyle(fontWeight:FontWeight.w700)),
            TextSpan(text:'escolhemos uma ficha publicada que cobre estes temas, com escolha múltipla e respostas abertas'
              '${child==null?'':' adequadas ao ${child!.schoolYear}.º ano'}.'),
          ]))),
      ])),
      const SizedBox(height:16),
      Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),
        decoration:BoxDecoration(color:AppColors.softBlue,borderRadius:BorderRadius.circular(AppRadii.pill)),
        child:Row(children:[
          Container(width:10,height:10,decoration:BoxDecoration(shape:BoxShape.circle,
            color:selectedTopics.isEmpty?AppColors.outline:const Color(0xFF10B981))),
          const SizedBox(width:10),
          Expanded(child:Text(selectedTopics.isEmpty?'Estado: escolhe pelo menos 1 tema'
            :'Estado: ${selectedTopics.length} ${selectedTopics.length==1?'tema selecionado':'temas selecionados'}',
            style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600,color:AppColors.text))),
        ])),
      feedback(),
      if(error!=null)TextButton(onPressed:busy||loading?null:(){if(subject==null){loadSubjects();}else{loadTopics();}},child:const Text('Atualizar catálogo')),
      const SizedBox(height:24),
      AppButton(label:'Ver Proposta de Ficha',icon:Icons.arrow_forward_rounded,loading:busy,onPressed:ready?propose:null),
      const SizedBox(height:6),
      const Text('Não precisas de escolher perguntas uma a uma.',textAlign:TextAlign.center,
        style:TextStyle(fontSize:14,color:AppColors.muted)),
    ]));
  }

  Widget proposalPage(){
    final item=worksheet!;
    final content=detail?['content'];final rawQuestions=content is Map?content['questions']:null;
    final questions=rawQuestions is List?rawQuestions.whereType<Map>().toList():<Map>[];
    return shell(onBack:busy?null:reset,body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      stepHeader(2,'Rever e Ajustar'),
      const SizedBox(height:20),
      Wrap(spacing:8,runSpacing:8,children:[
        AppBadge(label:'${item.subjectName} • ${item.schoolYear}.º Ano • ${item.topicNames.length} ${item.topicNames.length==1?'Tema':'Temas'}',
          icon:subjectIcon(item.subjectName)),
        AppBadge(label:'Para ${child!.displayName}',icon:Icons.face_rounded,background:AppColors.softBlue,color:AppColors.text),
        if(item.isSample)const AppBadge(label:'Ficha de exemplo',background:AppColors.amberSoft,color:AppColors.amber),
      ]),
      const SizedBox(height:16),
      const Text('Proposta de Ficha Preparada',style:TextStyle(fontSize:28,height:1.2,fontWeight:FontWeight.w800,color:AppColors.text)),
      const SizedBox(height:20),
      AppCard(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Wrap(spacing:8,runSpacing:8,children:[
          const AppBadge(label:'Proposta de Ficha Selecionada',icon:Icons.star_rounded,background:Color(0xFFFEA619),color:Color(0xFF4A2D00)),
          AppBadge(label:'Dimensão ${item.sizeLabel.toLowerCase()}',background:AppColors.successSoft,color:AppColors.success),
        ]),
        const SizedBox(height:18),
        Text(item.title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.primary)),
        const SizedBox(height:16),
        Row(children:[
          Container(width:92,padding:const EdgeInsets.symmetric(vertical:14),
            decoration:BoxDecoration(color:AppColors.lavender,borderRadius:BorderRadius.circular(22)),
            child:Column(children:[
              Text('${item.questionCount}',style:const TextStyle(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.primary)),
              const Text('PERGUNTAS',style:TextStyle(fontSize:11,letterSpacing:1,fontWeight:FontWeight.w700,color:AppColors.primary)),
            ])),
          const SizedBox(width:18),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Duração Estimada',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.text)),
            const SizedBox(height:4),
            Row(children:[
              const Icon(Icons.schedule_rounded,color:AppColors.primary,size:20),const SizedBox(width:6),
              Flexible(child:Text(duration(item),style:const TextStyle(fontSize:16,color:AppColors.muted))),
            ]),
            const SizedBox(height:2),
            const Text('Sem limite de tempo para a criança.',style:TextStyle(fontSize:13,color:AppColors.muted)),
          ])),
        ]),
      ])),
      if(proposals.length>1)...[
        sectionTitle('Outras propostas para estes temas'),
        Padding(padding:const EdgeInsets.only(bottom:12),
          child:searchField(worksheetSearch,'Pesquisar ficha por nome ou tema')),
        if(!proposals.any((candidate)=>worksheetMatches(candidate,worksheetSearch.text)))
          _HintBox('Nenhuma ficha encontrada para «${worksheetSearch.text.trim()}».'),
        for(final candidate in proposals.where((candidate)=>worksheetMatches(candidate,worksheetSearch.text)))Padding(padding:const EdgeInsets.only(bottom:10),child:AppCard(
          padding:const EdgeInsets.all(16),
          selected:candidate.versionId==item.versionId,onTap:busy?null:()=>chooseProposal(candidate),
          child:Row(children:[Icon(candidate.versionId==item.versionId?Icons.check_circle_rounded:Icons.circle_outlined,color:AppColors.primary),
            const SizedBox(width:12),Expanded(child:Text(candidate.title,style:const TextStyle(fontWeight:FontWeight.w600))),
            Text('${candidate.questionCount} perg.',style:const TextStyle(color:AppColors.muted))]))),
      ],
      Padding(padding:const EdgeInsets.only(top:28,bottom:14),child:Row(children:[
        const Icon(Icons.donut_large_rounded,color:AppColors.coral),const SizedBox(width:10),
        Expanded(child:Semantics(header:true,child:const Text('Composição da Ficha (conforme temas)',
          style:TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)))),
      ])),
      if(item.choiceCount>0)_CompositionCard(
        icon:Icons.checklist_rounded,iconBackground:AppColors.lavender,iconColor:AppColors.primary,
        title:'${item.choiceCount} ${item.choiceCount==1?'Pergunta Objetiva':'Perguntas Objetivas'}',
        badge:'Autonomia',badgeBackground:AppColors.lavender,badgeColor:AppColors.primary,
        text:'Escolha múltipla com correção automática. A criança vê o resultado sem esperar pela revisão.'),
      if(item.writtenCount>0)_CompositionCard(
        icon:Icons.lightbulb_outline_rounded,iconBackground:AppColors.coralSoft,iconColor:const Color(0xFFE5603E),
        title:'${item.writtenCount} ${item.writtenCount==1?'Pergunta Aberta / Reflexão':'Perguntas Abertas / Reflexão'}',
        badge:'Raciocínio',badgeBackground:AppColors.coralSoft,badgeColor:const Color(0xFFE5603E),
        text:'Precisam da tua revisão no Painel do Responsável. Escolhe abaixo onde a criança responde.'),
      if(item.writtenCount>0)...[
        Padding(padding:const EdgeInsets.only(top:16,bottom:10),child:Semantics(header:true,
          child:const Text('Onde responde às perguntas abertas?',
            style:TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)))),
        for(final (mode,icon,title,text) in const [
          ('typed',Icons.edit_rounded,'Escrever na app','A criança escreve a resposta aqui. Lês o texto na revisão.'),
          ('paper',Icons.menu_book_rounded,'No caderno','A criança resolve em papel e assinala que terminou. Confirmas no caderno.'),
        ])Padding(padding:const EdgeInsets.only(bottom:10),child:Semantics(
          button:true,selected:writtenAnswerMode==mode,inMutuallyExclusiveGroup:true,
          child:AppCard(padding:const EdgeInsets.all(16),selected:writtenAnswerMode==mode,
            onTap:busy?null:()=>setState((){if(writtenAnswerMode!=mode){writtenAnswerMode=mode;requestId=newRequestId();}}),
            child:Row(children:[
              Icon(writtenAnswerMode==mode?Icons.radio_button_checked_rounded:Icons.radio_button_off_rounded,color:AppColors.primary),
              const SizedBox(width:12),
              Icon(icon,color:AppColors.text),const SizedBox(width:10),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:AppColors.text)),
                Text(text,style:const TextStyle(fontSize:14,color:AppColors.muted)),
              ])),
            ])))),
      ],
      _Expandable(icon:Icons.layers_outlined,title:'Ver temas abrangidos nesta ficha',children:[
        for(final name in item.topicNames)Padding(padding:const EdgeInsets.only(bottom:8),child:Row(children:[
          const Icon(Icons.check_rounded,color:AppColors.success,size:20),const SizedBox(width:8),Expanded(child:Text(name))])),
      ]),
      if(questions.isNotEmpty)_Expandable(icon:Icons.visibility_outlined,title:'Pré-visualizar perguntas',children:[
        for(var i=0;i<questions.length;i++)Padding(padding:const EdgeInsets.only(bottom:12),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          CircleAvatar(radius:14,backgroundColor:AppColors.softBlue,child:Text('${i+1}',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700))),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('${questions[i]['prompt']}',style:const TextStyle(fontSize:15,height:1.4)),
            Text(questions[i]['type']=='written'?'Resposta aberta':questions[i]['type']=='true_false'?'Verdadeiro ou falso':'Escolha múltipla',
              style:const TextStyle(fontSize:13,color:AppColors.muted)),
          ])),
        ])),
      ]),
      feedback(),
      const SizedBox(height:24),
      AppButton(label:'Disponibilizar ficha a ${child!.displayName} 🚀',variant:AppButtonVariant.success,loading:busy,onPressed:busy?null:assign),
      const SizedBox(height:12),
      AppButton(label:'Voltar e mudar temas',icon:Icons.arrow_back_rounded,variant:AppButtonVariant.neutral,onPressed:busy?null:reset),
    ]));
  }

  Widget confirmation(){
    final item=worksheet!;
    return shell(title:'Ficha Disponibilizada',onBack:busy?null:widget.onClose,body:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Container(
        padding:const EdgeInsets.fromLTRB(24,24,24,28),
        decoration:BoxDecoration(
          borderRadius:BorderRadius.circular(36),
          gradient:const LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Color(0xFFEFF4FF),Color(0xFFEDE9FE)]),
          boxShadow:[BoxShadow(color:AppColors.primary.withValues(alpha:0.08),blurRadius:20,offset:const Offset(0,8))],
        ),
        child:Column(children:[
          const AppBadge(label:'Disponibilizada com Sucesso!',icon:Icons.check_circle_outline_rounded,background:Color(0xFF10B981),color:Colors.white),
          const SizedBox(height:24),
          ExcludeSemantics(child:SizedBox(width:150,height:140,child:Stack(children:[
            Positioned(left:0,top:0,child:Container(width:130,height:130,alignment:Alignment.center,
              decoration:BoxDecoration(color:Colors.white,shape:BoxShape.circle,
                boxShadow:[BoxShadow(color:AppColors.primary.withValues(alpha:0.12),blurRadius:18)]),
              child:Text(ChildAvatars.emoji(child!.avatarId),style:const TextStyle(fontSize:68)))),
            Positioned(right:0,bottom:0,child:Container(width:52,height:52,
              decoration:const BoxDecoration(color:Color(0xFFFBBF24),shape:BoxShape.circle,
                boxShadow:[BoxShadow(color:Color(0xFFD97706),offset:Offset(0,3))]),
              child:const Icon(Icons.star_rounded,color:Colors.white,size:30))),
          ]))),
          const SizedBox(height:18),
          Semantics(header:true,child:Text('Ficha pronta para ${child!.displayName}!',textAlign:TextAlign.center,
            style:const TextStyle(fontSize:28,height:1.2,fontWeight:FontWeight.w800,color:AppColors.text))),
          const SizedBox(height:10),
          Text.rich(TextSpan(style:const TextStyle(fontSize:16,height:1.5,color:AppColors.muted),children:[
            TextSpan(text:'A ficha de ${item.subjectName} já está visível no tablet ou telemóvel, no '),
            const TextSpan(text:'Espaço do Aluno',style:TextStyle(color:AppColors.primary,fontWeight:FontWeight.w700)),
            const TextSpan(text:'.'),
          ]),textAlign:TextAlign.center),
          const SizedBox(height:16),
          Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
            decoration:BoxDecoration(color:Colors.white.withValues(alpha:0.8),borderRadius:BorderRadius.circular(AppRadii.pill)),
            child:const Row(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.circle,color:Color(0xFF10B981),size:12),SizedBox(width:8),
              Flexible(child:Text('Ficha disponível no perfil da criança',style:TextStyle(fontSize:14,fontWeight:FontWeight.w600))),
            ])),
        ]),
      ),
      const SizedBox(height:20),
      AppCard(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          ExcludeSemantics(child:Container(width:56,height:56,
            decoration:BoxDecoration(color:AppColors.lavender,borderRadius:BorderRadius.circular(18)),
            child:Icon(subjectIcon(item.subjectName),color:AppColors.primary))),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('DISCIPLINA',style:TextStyle(fontSize:12,letterSpacing:1.2,fontWeight:FontWeight.w700,color:AppColors.muted)),
            Text('${item.subjectName} • ${item.schoolYear}.º Ano',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)),
          ])),
          AppBadge(label:'${item.questionCount} Perguntas',background:AppColors.coralSoft,color:const Color(0xFFE5603E)),
        ]),
        const SizedBox(height:16),
        Text(item.title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.primary)),
        const SizedBox(height:14),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Expanded(child:_InfoTile(icon:Icons.schedule_rounded,label:'Duração estimada',value:duration(item).replaceAll('minutos','min'))),
          const SizedBox(width:12),
          Expanded(child:_InfoTile(icon:Icons.menu_book_outlined,label:'Tópicos',value:item.topicNames.isEmpty?'—':item.topicNames.join(', '),small:true)),
        ]),
      ])),
      const SizedBox(height:16),
      _Expandable(icon:Icons.auto_stories_outlined,title:'O que acontece a seguir?',children:const [
        _NextStep(number:1,text:'A criança entra no seu espaço com o PIN e encontra a ficha em destaque.'),
        _NextStep(number:2,text:'As perguntas de escolha múltipla são corrigidas automaticamente.'),
        _NextStep(number:3,text:'As respostas abertas aparecem nas Revisões Pendentes do Painel do Responsável.'),
      ]),
      feedback(),
      const SizedBox(height:24),
      AppButton(label:'Ver no Perfil de ${child!.displayName} agora',icon:Icons.play_circle_outline_rounded,loading:busy,onPressed:busy?null:viewChild),
      const SizedBox(height:12),
      AppButton(label:'Voltar ao Painel do Responsável',icon:Icons.dashboard_outlined,variant:AppButtonVariant.secondary,onPressed:busy?null:widget.onClose),
      const SizedBox(height:8),
      Center(child:TextButton.icon(onPressed:busy?null:reset,icon:const Icon(Icons.add_rounded),
        label:const Text('Preparar outra ficha para mais tarde'),style:TextButton.styleFrom(foregroundColor:AppColors.muted))),
    ]));
  }
}

class _ChildOption extends StatelessWidget {
  const _ChildOption({required this.child,required this.selected,required this.onTap});
  final ChildProfile child;
  final bool selected;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Semantics(button:true,selected:selected,excludeSemantics:true,
    label:'${child.displayName}, ${child.schoolYear}.º Ano',
    child:Material(
      color:selected?AppColors.surface:AppColors.softBlue,
      elevation:selected?3:0,shadowColor:AppColors.primary.withValues(alpha:0.2),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22),
        side:BorderSide(color:selected?AppColors.lavender:Colors.transparent,width:1.5)),
      child:InkWell(borderRadius:BorderRadius.circular(22),onTap:onTap,child:Padding(
        padding:const EdgeInsets.fromLTRB(12,12,18,12),
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          CircleAvatar(radius:24,backgroundColor:AppColors.lavender,
            child:Text(ChildAvatars.emoji(child.avatarId),style:const TextStyle(fontSize:26))),
          const SizedBox(width:12),
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Text(child.displayName,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:AppColors.text)),
              if(selected)...[const SizedBox(width:6),const Icon(Icons.verified_rounded,color:AppColors.primary,size:20)],
            ]),
            Text('${child.schoolYear}.º Ano${selected?' • Selecionado':''}',style:const TextStyle(fontSize:14,color:AppColors.muted)),
          ]),
        ]))),
    ));
}

class _SubjectOption extends StatelessWidget {
  const _SubjectOption({required this.subject,required this.year,required this.selected,required this.onTap,this.topicCount});
  final SchoolSubject subject;
  final int? year;
  final bool selected;
  final int? topicCount;
  final VoidCallback? onTap;
  static const palette=[(AppColors.lavender,AppColors.primary),(AppColors.coralSoft,Color(0xFFE5603E)),
    (AppColors.successSoft,AppColors.success),(AppColors.amberSoft,AppColors.amber),(Color(0xFFDDF3FE),Color(0xFF0A7FB5))];
  @override Widget build(BuildContext context){
    final (tint,ink)=palette[subject.name.hashCode.abs()%palette.length];
    return Semantics(button:true,selected:selected,excludeSemantics:true,label:subject.name,child:AnimatedContainer(
      duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:150),
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(28),
        boxShadow:selected?[BoxShadow(color:AppColors.primary.withValues(alpha:0.14),blurRadius:18,offset:const Offset(0,8))]:null),
      child:Material(
        color:selected?AppColors.surface:AppColors.softBlue,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(28),
          side:BorderSide(color:selected?AppColors.lavender:AppColors.blueBorder,width:selected?2:1)),
        child:InkWell(borderRadius:BorderRadius.circular(28),onTap:onTap,child:Padding(padding:const EdgeInsets.all(18),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Container(width:52,height:52,decoration:BoxDecoration(color:tint,borderRadius:BorderRadius.circular(16)),
                child:Icon(subjectIcon(subject.name),color:ink,size:28)),
              const Spacer(),
              if(selected)const CircleAvatar(radius:14,backgroundColor:AppColors.primary,child:Icon(Icons.check_rounded,size:18,color:Colors.white)),
            ]),
            const SizedBox(height:16),
            Text(subject.name,maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.text)),
            const SizedBox(height:2),
            Text([if(year!=null)'$year.º Ano',if(topicCount!=null)'$topicCount ${topicCount==1?'tema':'temas'}'].join(' • '),
              style:const TextStyle(fontSize:14,color:AppColors.muted)),
          ]))),
      ),
    ));
  }
}

class _TopicOption extends StatelessWidget {
  const _TopicOption({required this.topic,required this.selected,required this.onTap,this.worksheets=const []});
  final SchoolTopic topic;
  /// Fichas deste tema cujo nome corresponde à pesquisa.
  final List<String> worksheets;
  final bool selected;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Semantics(checked:selected,button:true,excludeSemantics:true,
    label:worksheets.isEmpty?topic.name:'${topic.name}. Ficha: ${worksheets.join(', ')}',
    child:Material(
      color:selected?AppColors.surface:AppColors.softBlue,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22),
        side:BorderSide(color:selected?AppColors.lavender:Colors.transparent,width:1.5)),
      elevation:selected?2:0,shadowColor:AppColors.primary.withValues(alpha:0.15),
      child:InkWell(borderRadius:BorderRadius.circular(22),onTap:onTap,child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:16,vertical:18),
        child:Row(children:[
          AnimatedContainer(duration:const Duration(milliseconds:120),width:32,height:32,
            decoration:BoxDecoration(shape:BoxShape.circle,color:selected?const Color(0xFF58CC02):AppColors.blueBorder,
              boxShadow:selected?const [BoxShadow(color:Color(0xFF46A302),offset:Offset(0,2))]:null),
            child:selected?const Icon(Icons.check_rounded,color:Colors.white,size:22):null),
          const SizedBox(width:14),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(topic.name,style:TextStyle(fontSize:16,fontWeight:selected?FontWeight.w700:FontWeight.w600,color:AppColors.text)),
            if(worksheets.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),child:Row(children:[
              const Icon(Icons.description_outlined,size:16,color:AppColors.primary),const SizedBox(width:6),
              Expanded(child:Text('Ficha: «${worksheets.first}»${worksheets.length>1?' e mais ${worksheets.length-1}':''}',
                maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13,color:AppColors.primary,fontWeight:FontWeight.w600))),
            ])),
          ])),
        ]))),
    ));
}

class _HintBox extends StatelessWidget {
  const _HintBox(this.text);
  final String text;
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(18),margin:const EdgeInsets.only(bottom:10),
    decoration:BoxDecoration(color:AppColors.softBlue,borderRadius:BorderRadius.circular(20)),
    child:Text(text,style:const TextStyle(color:AppColors.muted)));
}

class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.icon,required this.iconBackground,required this.iconColor,required this.title,
    required this.badge,required this.badgeBackground,required this.badgeColor,required this.text});
  final IconData icon;
  final Color iconBackground,iconColor,badgeBackground,badgeColor;
  final String title,badge,text;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:14),child:AppCard(
    padding:const EdgeInsets.all(20),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      ExcludeSemantics(child:Container(width:52,height:52,
        decoration:BoxDecoration(color:iconBackground,borderRadius:BorderRadius.circular(16)),
        child:Icon(icon,color:iconColor))),
      const SizedBox(width:14),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Wrap(spacing:8,runSpacing:6,crossAxisAlignment:WrapCrossAlignment.center,children:[
          Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:AppColors.text)),
          AppBadge(label:badge,background:badgeBackground,color:badgeColor),
        ]),
        const SizedBox(height:8),
        Text(text,style:const TextStyle(fontSize:15,height:1.45,color:AppColors.muted)),
      ])),
    ]),
  ));
}

class _Expandable extends StatelessWidget {
  const _Expandable({required this.icon,required this.title,required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:14),child:AppCard(
    padding:EdgeInsets.zero,
    child:Theme(data:Theme.of(context).copyWith(dividerColor:Colors.transparent),child:ExpansionTile(
      tilePadding:const EdgeInsets.symmetric(horizontal:20,vertical:4),
      childrenPadding:const EdgeInsets.fromLTRB(20,0,20,12),
      leading:Icon(icon,color:AppColors.primary),
      title:Text(title,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:AppColors.text)),
      expandedCrossAxisAlignment:CrossAxisAlignment.stretch,
      children:children,
    )),
  ));
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon,required this.label,required this.value,this.small=false});
  final IconData icon;
  final String label,value;
  final bool small;
  @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(14),
    decoration:BoxDecoration(color:AppColors.softBlue,borderRadius:BorderRadius.circular(20)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Icon(icon,size:18,color:AppColors.muted),const SizedBox(width:6),
        Flexible(child:Text(label,style:const TextStyle(fontSize:13,color:AppColors.muted)))]),
      const SizedBox(height:6),
      Text(value,maxLines:2,overflow:TextOverflow.ellipsis,
        style:TextStyle(fontSize:small?15:20,fontWeight:FontWeight.w700,color:AppColors.text)),
    ]));
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.number,required this.text});
  final int number;
  final String text;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:12),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    CircleAvatar(radius:13,backgroundColor:AppColors.lavender,
      child:Text('$number',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w800,color:AppColors.primary))),
    const SizedBox(width:12),
    Expanded(child:Text(text,style:const TextStyle(fontSize:15,height:1.45))),
  ]));
}
