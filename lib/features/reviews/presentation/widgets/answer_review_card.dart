import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_badge.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/parent_review_models.dart';
import 'review_classification_selector.dart';

class AnswerReviewCard extends StatelessWidget {
  const AnswerReviewCard({super.key, required this.question, required this.number,
    required this.childName, required this.onClassify, this.enabled = true, this.saving = false});
  final ParentReviewQuestion question;
  final int number;
  final String childName;
  final ValueChanged<ReviewClassification> onClassify;
  final bool enabled, saving;

  @override
  Widget build(BuildContext context) {
    final review = question.review;
    final multipleChoice = question.type == 'multiple-choice';
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Pergunta $number • ${multipleChoice ? 'Escolha múltipla' : 'Resposta aberta'}', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 14),
      SelectableText(question.prompt, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 20),
      Text('Resposta de $childName', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (multipleChoice) ...[
        Text(question.optionText(question.selectedOptionId)), const SizedBox(height: 12),
        AppBadge(label: question.answerType != 'multiple-choice' ? 'Sem resposta'
          : question.selectedOptionId == question.correctOptionId ? 'Correta' : 'Incorreta', icon: Icons.fact_check_outlined),
        const SizedBox(height: 12), Text('Resposta correta: ${question.optionText(question.correctOptionId)}'),
        const SizedBox(height: 8), const Text('Correção automática. Não necessita de classificação parental.'),
      ] else if (question.answerType == 'paper') ...[
        const AppBadge(label: 'Respondido no caderno', icon: Icons.menu_book_rounded),
        const SizedBox(height: 12), const Text('Consulta o caderno da criança para conferir a resposta e o raciocínio antes de classificar.'),
      ] else if (question.reviewable) ...[
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
          color: AppColors.softBlue, borderRadius: BorderRadius.circular(AppRadii.input)),
          child: SelectableText(question.text ?? '', style: Theme.of(context).textTheme.bodyLarge)),
      ] else ...[
        const AppBadge(label: 'Sem resposta', icon: Icons.remove_rounded),
        const SizedBox(height: 8), const Text('Esta pergunta ficou em branco e não necessita de revisão.'),
      ],
      if (question.explanation.isNotEmpty) ...[
        const SizedBox(height: 12), ExpansionTile(title: const Text('Orientação para a correção'),
          children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(question.explanation))]),
      ],
      if (question.reviewable) ...[
        const SizedBox(height: 22),
        Text('Classificação', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6), const Text('Cada escolha é guardada imediatamente.'),
        const SizedBox(height: 12),
        ReviewClassificationSelector(value: review?.classification, enabled: enabled, onChanged: onClassify),
        const SizedBox(height: 12),
        if (saving) const Row(children: [SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('A confirmar a classificação…')])
        else if (review != null) Text('Guardada • ${date(review.reviewedAt.toLocal())}', style: Theme.of(context).textTheme.bodySmall)
        else const Text('Por rever. Escolhe uma classificação após consultar a resposta.'),
      ],
    ]));
  }

  String date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
