import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../app_card.dart';

class SubjectCard extends StatelessWidget {
  const SubjectCard(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.onTap,
      this.selected = false});
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => AppCard(
        selected: selected,
        onTap: onTap,
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.amberSoft,
                  borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: AppColors.amber, size: 30)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle)
              ])),
          const SizedBox(width: 8),
          Icon(selected ? Icons.check_circle : Icons.chevron_right_rounded,
              color: AppColors.primary),
        ]),
      );
}
