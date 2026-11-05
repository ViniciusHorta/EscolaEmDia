import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../domain/submission_summary.dart';

class SubmissionSummaryPage extends StatelessWidget {
  const SubmissionSummaryPage({super.key,required this.summary,required this.onClose,required this.onParents,this.onViewLocalDraft});
  final SubmissionSummary summary;
  final VoidCallback onClose,onParents;
  final VoidCallback? onViewLocalDraft;
  @override Widget build(BuildContext context)=>AppPage(title:'Muito bem!',subtitle:'A tua ficha foi entregue.',children:[
    AppCard(color:AppColors.lavender,child:Column(children:[
      const Icon(Icons.stars_rounded,size:80,color:AppColors.primary),const SizedBox(height:20),
      Text(summary.title,textAlign:TextAlign.center,style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:16),
      const Text('Fizeste tudo ao teu ritmo. Obrigado pelo teu esforço!',textAlign:TextAlign.center),
      const SizedBox(height:20),AppBadge(label:summary.pendingReview>0?'Aguarda revisão parental':'Concluída',icon:Icons.check_circle_outline_rounded),
    ])),
    const SizedBox(height:24),AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Resumo da tua ficha',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:18),
      if(summary.choiceTotal>0)Text('${summary.choiceCorrect} certas em ${summary.choiceTotal} perguntas de escolha múltipla.',style:Theme.of(context).textTheme.bodyLarge),
      if(summary.pendingReview>0)...[const SizedBox(height:16),Text('${summary.pendingReview} respostas vão ser revistas pelos teus pais.')],
      if(summary.writtenCorrect+summary.writtenPartial+summary.writtenIncorrect>0)...[
        const SizedBox(height:16),Text('Nas respostas abertas revistas: ${summary.writtenCorrect} corretas, ${summary.writtenPartial} parcialmente corretas e ${summary.writtenIncorrect} incorretas.'),
      ],
      if(summary.unansweredTotal>0)...[const SizedBox(height:16),Text('${summary.unansweredTotal} perguntas ficaram sem resposta.')],
      if(summary.choiceTotal==0)...[const SizedBox(height:16),const Text('O teu trabalho ficou guardado, sem nota automática.')],
    ])),
    if(onViewLocalDraft!=null)...[
      const SizedBox(height:20),const AppCard(child:Text('Existem alterações neste dispositivo que não foram incluídas na entrega confirmada. Podes consultá-las sem alterar a ficha entregue.')),
      const SizedBox(height:12),AppButton(label:'Consultar alterações locais',variant:AppButtonVariant.secondary,onPressed:onViewLocalDraft),
    ],
    const SizedBox(height:28),AppButton(label:'Voltar ao meu espaço',icon:Icons.home_outlined,onPressed:onClose),
    const SizedBox(height:16),TextButton.icon(onPressed:onParents,icon:const Icon(Icons.lock_outline_rounded),label:const Text('Área dos pais')),
  ]);
}
