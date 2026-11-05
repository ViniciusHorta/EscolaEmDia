import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';

class ProgressStatCard extends StatelessWidget {
  const ProgressStatCard({super.key, required this.label, required this.value, required this.icon});
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: AppColors.primary), const SizedBox(height: 12),
    Text('$value', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 6), Text(label),
  ]));
}
