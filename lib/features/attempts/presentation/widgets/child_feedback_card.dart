import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/child_feedback_models.dart';

class ChildFeedbackCard extends StatelessWidget {
  const ChildFeedbackCard({super.key, required this.question});
  final ChildFeedbackQuestion question;
  @override
  Widget build(BuildContext context) {
    final (label, color, background, icon) = switch (question.outcome) {
      'correct' => ('Correta', AppColors.success, AppColors.successSoft, Icons.check_circle_outline_rounded),
      'partially_correct' => ('Parcialmente correta', AppColors.amber, AppColors.amberSoft, Icons.contrast_rounded),
      'incorrect' => ('Incorreta', AppColors.error, AppColors.coralSoft, Icons.refresh_rounded),
      'pending_review' => ('Aguarda revisão', AppColors.amber, AppColors.amberSoft, Icons.hourglass_empty_rounded),
      _ => ('Sem resposta', AppColors.muted, AppColors.softBlue, Icons.remove_rounded),
    };
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: Text('Pergunta ${question.number}', style: Theme.of(context).textTheme.titleMedium))]),
      const SizedBox(height: 12), SelectableText(question.prompt, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16), AppBadge(label: label, color: color, background: background, icon: icon),
      const SizedBox(height: 18), Text('A tua resposta', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (question.outcome == 'unanswered') const Text('Esta pergunta ficou sem resposta.')
      else if (question.automatic) SelectableText(question.selectedOptionText ?? 'Não foi possível ler a opção escolhida.')
      else if (question.answerType == 'paper') const Text('Respondeste no caderno. Podes olhar para a tua resolução enquanto vês a correção.')
      else SelectableText(question.answerText),
      if (question.automatic && question.needsPractice && question.correctOptionText != null) ...[
        const SizedBox(height: 18), Text('Resposta correta', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8), Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(AppRadii.input)),
          child: SelectableText(question.correctOptionText!)),
      ],
      if (question.type == 'written' && question.outcome != 'unanswered') ...[
        const SizedBox(height: 14), Text(question.outcome == 'pending_review'
          ? 'Os teus pais ainda vão rever esta resposta.' : 'Esta é a classificação que os teus pais deram à tua resposta.'),
        if (question.outcome == 'incorrect' || question.outcome == 'partially_correct') ...[
          const SizedBox(height: 8), const Text('Conversa com os teus pais sobre o que podes melhorar e volta a tentar quando quiseres.'),
        ],
      ],
      if (question.explanation.isNotEmpty) ...[
        const SizedBox(height: 18), Text('Vamos perceber', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8), SelectableText(question.explanation),
      ],
    ]));
  }
}
