import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/attempt_models.dart';

class QuestionAnswerEditor extends StatefulWidget {
  const QuestionAnswerEditor({super.key,required this.question,required this.value,required this.enabled,required this.onChanged});
  final AttemptQuestion question;
  final Map<String,dynamic> value;
  final bool enabled;
  final ValueChanged<Map<String,dynamic>> onChanged;
  @override State<QuestionAnswerEditor> createState()=>_QuestionAnswerEditorState();
}
class _QuestionAnswerEditorState extends State<QuestionAnswerEditor> {
  late final TextEditingController text;
  bool paper=false;
  @override void initState(){super.initState();text=TextEditingController(text:widget.value['text'] as String? ?? '');paper=widget.value['mode']=='paper';}
  @override void didUpdateWidget(covariant QuestionAnswerEditor oldWidget){
    super.didUpdateWidget(oldWidget);
    if(widget.value['mode']=='typed'&&widget.value['text']!=text.text)text.text=widget.value['text'] as String? ?? '';
    if(widget.value['mode']=='paper')paper=true;
  }
  @override void dispose(){text.dispose();super.dispose();}
  void write(String value)=>widget.onChanged(value.trim().isEmpty?{'mode':'unanswered'}:{'mode':'typed','text':value});
  @override Widget build(BuildContext context){
    if(widget.question.type=='multiple-choice')return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      for(var i=0;i<widget.question.options.length;i++)Padding(padding:const EdgeInsets.only(bottom:16),child:_ChoiceOption(
        letter:String.fromCharCode(65+i),
        text:widget.question.options[i].text,
        selected:widget.value['selectedOptionId']==widget.question.options[i].id,
        onTap:widget.enabled?()=>widget.onChanged({'mode':'multiple-choice','selectedOptionId':widget.question.options[i].id}):null,
      )),
      if(widget.value['mode']=='multiple-choice')Align(alignment:Alignment.center,child:TextButton.icon(
        onPressed:widget.enabled?()=>widget.onChanged({'mode':'unanswered'}):null,
        icon:const Icon(Icons.refresh_rounded),label:const Text('Limpar resposta'))),
    ]);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      _ModeToggle(paper:paper,enabled:widget.enabled,
        onWrite:(){setState(()=>paper=false);write(text.text);},
        onPaper:(){setState(()=>paper=true);widget.onChanged({'mode':'unanswered'});}),
      const SizedBox(height:20),
      AppCard(child:paper?Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Row(children:[
          Icon(Icons.menu_book_rounded,color:AppColors.primary),SizedBox(width:10),
          Expanded(child:Text('No teu caderno',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:AppColors.text))),
        ]),
        const SizedBox(height:10),
        const Text('Resolve a pergunta no teu caderno. Depois, assinala que já terminaste.',style:TextStyle(color:AppColors.muted,fontSize:15)),
        const SizedBox(height:12),
        CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Já resolvi o desafio no meu caderno'),
          value:widget.value['mode']=='paper',onChanged:widget.enabled?(checked)=>widget.onChanged({'mode':checked==true?'paper':'unanswered'}):null),
      ]):Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          const Icon(Icons.draw_rounded,color:AppColors.primary,size:24),const SizedBox(width:10),
          const Expanded(child:Text('A tua explicação:',style:TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:AppColors.text))),
          ListenableBuilder(listenable:text,builder:(context,_)=>Text('${text.text.characters.length} caracteres',
            style:const TextStyle(color:AppColors.muted,fontSize:14,fontWeight:FontWeight.w600))),
        ]),
        const SizedBox(height:14),
        Stack(children:[
          TextField(controller:text,enabled:widget.enabled,minLines:5,maxLines:10,maxLength:5000,
            onChanged:write,style:const TextStyle(fontSize:17,height:1.45,color:AppColors.text),
            decoration:InputDecoration(
              hintText:'Escreve aqui a tua estratégia e passos…',
              counterText:'',filled:true,fillColor:AppColors.softBlue,
              contentPadding:const EdgeInsets.fromLTRB(20,18,56,18),
              border:OutlineInputBorder(borderRadius:BorderRadius.circular(AppRadii.input),borderSide:BorderSide.none),
              enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(AppRadii.input),borderSide:BorderSide.none),
              focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(AppRadii.input),
                borderSide:const BorderSide(color:AppColors.primary,width:2)),
            )),
          Positioned(right:8,bottom:8,child:ListenableBuilder(listenable:text,builder:(context,_)=>text.text.isEmpty
            ?const SizedBox.shrink()
            :IconButton.filledTonal(tooltip:'Apagar resposta',
              onPressed:widget.enabled?(){text.clear();write('');}:null,
              icon:const Icon(Icons.backspace_outlined)))),
        ]),
      ])),
    ]);
  }
}

/// Opção de escolha múltipla em pílula tátil, com letra e marca de seleção.
class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({required this.letter,required this.text,required this.selected,required this.onTap});
  final String letter,text;
  final bool selected;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Semantics(
    button:true,selected:selected,inMutuallyExclusiveGroup:true,label:'Opção $letter: $text',excludeSemantics:true,
    child:AnimatedContainer(
      duration:MediaQuery.disableAnimationsOf(context)?Duration.zero:const Duration(milliseconds:120),
      decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(40),
        boxShadow:[BoxShadow(color:selected?const Color(0xFFC7BFFF):AppColors.blueBorder,offset:const Offset(0,5))],
      ),
      child:Material(
        color:selected?AppColors.lavender:AppColors.surface,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(40),
          side:BorderSide(color:selected?const Color(0xFFC7BFFF):AppColors.blueBorder,width:selected?2:1.5)),
        clipBehavior:Clip.antiAlias,
        child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:16),child:Row(children:[
          CircleAvatar(radius:26,backgroundColor:selected?AppColors.primary:AppColors.softBlue,
            child:Text(letter,style:TextStyle(color:selected?Colors.white:AppColors.text,fontSize:20,fontWeight:FontWeight.w800))),
          const SizedBox(width:16),
          Expanded(child:Text(text,style:TextStyle(fontSize:19,fontWeight:FontWeight.w700,height:1.3,
            color:selected?AppColors.primary:AppColors.text))),
          const SizedBox(width:12),
          selected
            ?const CircleAvatar(radius:20,backgroundColor:AppColors.primary,child:Icon(Icons.check_rounded,color:Colors.white,size:24))
            :const CircleAvatar(radius:20,backgroundColor:AppColors.softBlue),
        ]))),
      ),
    ),
  );
}

/// Alternância «Escrever aqui» / «No caderno» em pílulas dentro de uma calha.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.paper,required this.enabled,required this.onWrite,required this.onPaper});
  final bool paper,enabled;
  final VoidCallback onWrite,onPaper;
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.all(8),
    decoration:BoxDecoration(color:AppColors.blueBorder.withValues(alpha:0.6),borderRadius:BorderRadius.circular(AppRadii.pill)),
    child:Row(children:[
      Expanded(child:_pill('Escrever aqui',Icons.edit_rounded,!paper,enabled&&paper?onWrite:null)),
      const SizedBox(width:8),
      Expanded(child:_pill('No caderno',Icons.edit_note_rounded,paper,enabled&&!paper?onPaper:null)),
    ]),
  );
  Widget _pill(String label,IconData icon,bool selected,VoidCallback? onTap)=>Semantics(
    button:true,selected:selected,excludeSemantics:true,label:label,
    child:Container(
      decoration:BoxDecoration(borderRadius:BorderRadius.circular(AppRadii.pill),
        boxShadow:[BoxShadow(color:selected?AppColors.primaryPressed:AppColors.blueBorder,offset:const Offset(0,4))]),
      child:Material(
        color:selected?AppColors.primary:AppColors.surface,
        shape:const StadiumBorder(),
        child:InkWell(customBorder:const StadiumBorder(),onTap:onTap,child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:12,vertical:14),
          child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            Icon(icon,size:22,color:selected?Colors.white:AppColors.text),const SizedBox(width:8),
            Flexible(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(fontSize:16,fontWeight:FontWeight.w700,color:selected?Colors.white:AppColors.text))),
          ]))),
      ),
    ),
  );
}
