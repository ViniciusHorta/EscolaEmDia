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
      for(var i=0;i<widget.question.options.length;i++)Padding(padding:const EdgeInsets.only(bottom:14),child:AppCard(
        selected:widget.value['selectedOptionId']==widget.question.options[i].id,
        onTap:widget.enabled?()=>widget.onChanged({'mode':'multiple-choice','selectedOptionId':widget.question.options[i].id}):null,
        child:Row(children:[
          CircleAvatar(backgroundColor:AppColors.lavender,child:Text(String.fromCharCode(65+i),style:const TextStyle(color:AppColors.primary,fontWeight:FontWeight.w700))),
          const SizedBox(width:16),Expanded(child:Text(widget.question.options[i].text,style:Theme.of(context).textTheme.bodyLarge)),
          if(widget.value['selectedOptionId']==widget.question.options[i].id)const Icon(Icons.check_circle_rounded,color:AppColors.primary),
        ]))),
      Align(alignment:Alignment.centerLeft,child:TextButton(onPressed:widget.enabled?()=>widget.onChanged({'mode':'unanswered'}):null,child:const Text('Limpar resposta'))),
    ]);
    return AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Wrap(spacing:10,runSpacing:10,children:[
        ChoiceChip(label:const Text('Escrever aqui'),selected:!paper,onSelected:widget.enabled?(_){setState(()=>paper=false);write(text.text);}:null),
        ChoiceChip(label:const Text('No caderno'),selected:paper,onSelected:widget.enabled?(_){setState(()=>paper=true);widget.onChanged({'mode':'unanswered'});}:null),
      ]),
      const SizedBox(height:20),
      if(!paper)...[
        TextField(controller:text,enabled:widget.enabled,minLines:4,maxLines:8,maxLength:5000,
          onChanged:write,decoration:const InputDecoration(labelText:'A tua explicação',hintText:'Conta como pensaste…',alignLabelWithHint:true)),
        Align(alignment:Alignment.centerLeft,child:TextButton(onPressed:widget.enabled?(){text.clear();write('');}:null,child:const Text('Limpar resposta'))),
      ]else ...[
        const Text('Resolve a pergunta no teu caderno. Depois, assinala que já terminaste.'),
        const SizedBox(height:14),
        CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Já resolvi o desafio no meu caderno'),
          value:widget.value['mode']=='paper',onChanged:widget.enabled?(checked)=>widget.onChanged({'mode':checked==true?'paper':'unanswered'}):null),
      ],
    ]));
  }
}
