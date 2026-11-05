import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/worksheet_models.dart';

class AssignedWorksheetCard extends StatelessWidget {
  const AssignedWorksheetCard({super.key,required this.assignment});
  final AssignedWorksheet assignment;
  @override Widget build(BuildContext context){
    final item=assignment.worksheet;
    return AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Wrap(spacing:8,runSpacing:8,children:[
        const AppBadge(label:'Preparada pelos teus pais',icon:Icons.favorite_border_rounded),
        AppBadge(label:'${item.questionCount} perguntas',icon:Icons.quiz_outlined),
        if(item.isSample)const AppBadge(label:'Ficha de exemplo',background:AppColors.amberSoft,color:AppColors.amber),
      ]),
      const SizedBox(height:20),
      Text(item.title,style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:10),Text(item.topicNames.join(' • ')),
      const SizedBox(height:16),const Align(alignment:Alignment.centerLeft,
        child:AppBadge(label:'Por começar',icon:Icons.menu_book_rounded)),
    ]));
  }
}
