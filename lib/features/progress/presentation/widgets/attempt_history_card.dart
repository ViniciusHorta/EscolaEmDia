import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/child_progress_models.dart';

class AttemptHistoryCard extends StatelessWidget {
  const AttemptHistoryCard({super.key, required this.attempt, required this.onReview});
  final AttemptHistoryEntry attempt;
  final VoidCallback onReview;
  @override
  Widget build(BuildContext context) {
    final summary = attempt.summary;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(attempt.title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      Text('${attempt.subjectName} • ${attempt.questionCount} perguntas'), const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppBadge(label: historyStatusLabel(attempt.status),
          background: attempt.status == 'completed' ? AppColors.successSoft : AppColors.lavender,
          color: attempt.status == 'completed' ? AppColors.success : AppColors.primary),
        if (!attempt.assignmentActive) const AppBadge(label: 'Atribuição retirada', icon: Icons.history_rounded),
      ]),
      const SizedBox(height: 14), Text('Iniciada em ${date(attempt.startedAt.toLocal())}'),
      if (attempt.submittedAt != null) Text('Entregue em ${date(attempt.submittedAt!.toLocal())}'),
      if (summary != null) ...[
        const SizedBox(height: 14),
        if (summary.choiceTotal > 0) Text('${summary.choiceCorrect} de ${summary.choiceTotal} escolhas múltiplas corretas.'),
        Text('Abertas: ${summary.writtenCorrect} corretas • ${summary.writtenPartial} parcialmente corretas • ${summary.writtenIncorrect} incorretas.'),
        if (summary.pendingReview > 0) Text('${summary.pendingReview} respostas por rever.'),
        if (summary.unansweredTotal > 0) Text('${summary.unansweredTotal} perguntas sem resposta.'),
        const SizedBox(height: 16), AppButton(label: summary.pendingReview > 0 ? 'Rever respostas' : 'Consultar entrega',
          icon: Icons.fact_check_outlined, variant: AppButtonVariant.secondary, onPressed: onReview),
      ] else ...[
        const SizedBox(height: 12), const Text('Esta realização ainda não tem uma entrega para consultar.'),
      ],
    ]));
  }
  String date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
