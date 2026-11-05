import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/child_progress_models.dart';

class SubjectProgressCard extends StatelessWidget {
  const SubjectProgressCard({super.key, required this.subject});
  final SubjectProgress subject;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(subject.name, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 14),
    Wrap(spacing: 10, runSpacing: 8, children: [
      AppBadge(label: '${subject.totals.delivered} entregas', icon: Icons.cloud_done_outlined),
      AppBadge(label: '${subject.totals.completed} concluídas', background: AppColors.successSoft, color: AppColors.success),
      if (subject.totals.pendingAnswers > 0) AppBadge(label: '${subject.totals.pendingAnswers} respostas por rever',
        background: AppColors.amberSoft, color: AppColors.amber),
    ]),
    const SizedBox(height: 16),
    Text('${subject.totals.toStart} por começar • ${subject.totals.inProgress} em curso'),
    if (subject.totals.delivered == 0) ...[
      const SizedBox(height: 12), const Text('Os resultados aparecem após a entrega da primeira ficha desta disciplina.'),
    ] else ...[
      const SizedBox(height: 16), Text('Escolhas múltiplas', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6), Text('${subject.choiceCorrect} corretas em ${subject.choiceTotal} perguntas.'),
      const SizedBox(height: 16), Text('Respostas abertas', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6), Text('${subject.writtenCorrect} corretas • ${subject.writtenPartial} parcialmente corretas • ${subject.writtenIncorrect} incorretas.'),
      if (subject.totals.pendingAnswers > 0) ...[const SizedBox(height: 6), Text('${subject.totals.pendingAnswers} respostas aguardam classificação.')],
      const SizedBox(height: 12), Text('${subject.unansweredTotal} perguntas ficaram sem resposta nas entregas.'),
    ],
  ]));
}
