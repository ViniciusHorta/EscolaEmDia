import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/parent_review_models.dart';

class ReviewClassificationSelector extends StatelessWidget {
  const ReviewClassificationSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final ReviewClassification? value;
  final ValueChanged<ReviewClassification> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
    for (final classification in ReviewClassification.values)
      ChoiceChip(
        label: Text(classification.label), selected: value == classification,
        avatar: Icon(switch (classification) {
          ReviewClassification.correct => Icons.check_rounded,
          ReviewClassification.partiallyCorrect => Icons.contrast_rounded,
          ReviewClassification.incorrect => Icons.close_rounded,
        }, size: 20),
        selectedColor: switch (classification) {
          ReviewClassification.correct => AppColors.successSoft,
          ReviewClassification.partiallyCorrect => AppColors.amberSoft,
          ReviewClassification.incorrect => AppColors.coralSoft,
        },
        onSelected: enabled ? (selected) { if (selected && value != classification) onChanged(classification); } : null,
      ),
  ]);
}
