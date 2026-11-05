import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../domain/worksheet_models.dart';

class AssignedWorksheetCard extends StatelessWidget {
  const AssignedWorksheetCard({super.key,required this.assignment,this.onStart,this.onRepeat,this.onViewFeedback});
  final AssignedWorksheet assignment;
  final VoidCallback? onStart,onRepeat,onViewFeedback;
  @override Widget build(BuildContext context){
    final item=assignment.worksheet;
    return AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Wrap(spacing:8,runSpacing:8,children:[
        const AppBadge(label:'Preparada pelos teus pais',icon:Icons.favorite_border_rounded),
        AppBadge(label:'${item.questionCount} perguntas',icon:Icons.quiz_outlined),
        if(assignment.latestAttemptNumber!=null)AppBadge(label:'Tentativa ${assignment.latestAttemptNumber}',icon:Icons.history_rounded),
        if(item.isSample)const AppBadge(label:'Ficha de exemplo',background:AppColors.amberSoft,color:AppColors.amber),
      ]),
      const SizedBox(height:20),
      Text(item.title,style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:10),Text(item.topicNames.join(' • ')),
      const SizedBox(height:16),Align(alignment:Alignment.centerLeft,
        child:AppBadge(label:assignment.activeAttemptId!=null?'Em pausa':assignment.latestAttemptStatus=='pending_review'?'Aguarda revisão':assignment.latestAttemptStatus=='completed'?'Concluída':assignment.latestAttemptId!=null?'Entregue':'Por começar',icon:Icons.menu_book_rounded)),
      const SizedBox(height:20),
      AppButton(label:assignment.activeAttemptId!=null?'Continuar':assignment.latestAttemptId!=null?'Ver entrega':'Começar',icon:Icons.play_arrow_rounded,onPressed:onStart),
      if(assignment.latestCompletedAttemptId!=null)...[
        const SizedBox(height:14),AppButton(label:assignment.latestCompletedAttemptNumber==null?'Ver a correção':
          'Ver correção da tentativa ${assignment.latestCompletedAttemptNumber}',variant:AppButtonVariant.secondary,
          icon:Icons.fact_check_outlined,onPressed:onViewFeedback),
      ],
      if(assignment.canRepeat)...[
        const SizedBox(height:14),AppButton(label:'Fazer outra vez',variant:AppButtonVariant.secondary,icon:Icons.replay_rounded,onPressed:onRepeat),
      ],
    ]));
  }
}
