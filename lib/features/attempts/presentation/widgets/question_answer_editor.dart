import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/attempt_models.dart';

class QuestionAnswerEditor extends StatefulWidget {
  const QuestionAnswerEditor({super.key,required this.question,required this.value,required this.enabled,required this.onChanged,
    this.writtenAnswerMode='typed'});
  final AttemptQuestion question;
  /// Definido pelo responsável na atribuição: 'typed' (escreve aqui) ou 'paper' (no caderno). A criança não escolhe.
  final String writtenAnswerMode;
  final Map<String,dynamic> value;
  final bool enabled;
  final ValueChanged<Map<String,dynamic>> onChanged;
  @override State<QuestionAnswerEditor> createState()=>_QuestionAnswerEditorState();
}
class _QuestionAnswerEditorState extends State<QuestionAnswerEditor> {
  late final TextEditingController text;
  bool get paper=>widget.writtenAnswerMode=='paper';
  @override void initState(){super.initState();text=TextEditingController(text:widget.value['text'] as String? ?? '');}
  @override void didUpdateWidget(covariant QuestionAnswerEditor oldWidget){
    super.didUpdateWidget(oldWidget);
    if(widget.value['mode']=='typed'&&widget.value['text']!=text.text)text.text=widget.value['text'] as String? ?? '';
  }
  @override void dispose(){text.dispose();super.dispose();}
  void write(String value)=>widget.onChanged(value.trim().isEmpty?{'mode':'unanswered'}:{'mode':'typed','text':value});
  @override Widget build(BuildContext context){
    if(widget.question.type=='true_false'){
      final selected=widget.value['mode']=='true_false'?widget.value['value']:null;
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        for(final (value,label,icon) in const [(true,'Verdadeiro',Icons.check_rounded),(false,'Falso',Icons.close_rounded)])
          Padding(padding:const EdgeInsets.only(bottom:16),child:_ChoiceOption(
            text:label,icon:icon,
            selected:selected==value,
            onTap:widget.enabled?()=>widget.onChanged({'mode':'true_false','value':value}):null,
          )),
        if(selected!=null)Align(alignment:Alignment.center,child:TextButton.icon(
          onPressed:widget.enabled?()=>widget.onChanged({'mode':'unanswered'}):null,
          icon:const Icon(Icons.refresh_rounded),label:const Text('Limpar resposta'))),
      ]);
    }
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

/// Opção em pílula tátil (escolha múltipla com letra; Verdadeiro/Falso com ícone) e marca de seleção.
class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({this.letter,this.icon,required this.text,required this.selected,required this.onTap});
  final String? letter;
  final IconData? icon;
  final String text;
  final bool selected;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Semantics(
    button:true,selected:selected,inMutuallyExclusiveGroup:true,label:letter==null?text:'Opção $letter: $text',excludeSemantics:true,
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
            child:icon!=null?Icon(icon,color:selected?Colors.white:AppColors.text,size:26)
              :Text(letter!,style:TextStyle(color:selected?Colors.white:AppColors.text,fontSize:20,fontWeight:FontWeight.w800))),
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
