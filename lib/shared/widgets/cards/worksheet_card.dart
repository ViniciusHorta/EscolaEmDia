import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../app_badge.dart';
import '../app_button.dart';
import '../app_card.dart';

class WorksheetCard extends StatelessWidget {
  const WorksheetCard(
      {super.key,
      required this.title,
      required this.description,
      required this.questionCount,
      required this.onStart,
      this.actionLabel = 'Começar'});
  final String title;
  final String description;
  final int questionCount;
  final VoidCallback onStart;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          const AppBadge(
              label: 'Preparada pelos teus pais',
              icon: Icons.favorite_border,
              color: Color(0xFF9B321B),
              background: AppColors.coralSoft),
          AppBadge(
              label: '$questionCount perguntas', icon: Icons.quiz_outlined),
        ]),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        AppButton(
            label: actionLabel, icon: Icons.edit_rounded, onPressed: onStart),
      ]));
}
