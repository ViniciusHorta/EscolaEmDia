import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({super.key, required this.title, required this.step, required this.onBack, this.total = 4, this.section = 'Segurança', this.icon = Icons.lock_outline_rounded});
  final String title;
  final int step;
  final int total;
  final String section;
  final IconData icon;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [
      IconButton.filledTonal(onPressed: onBack, tooltip: 'Voltar', icon: const Icon(Icons.arrow_back_rounded)),
      const SizedBox(width: 12),
      Expanded(child: Column(children: [
        Text('PASSO $step DE $total • ${section.toUpperCase()}', textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      ])),
      const SizedBox(width: 12),
      CircleAvatar(backgroundColor: AppColors.lavender, child: Icon(icon, color: AppColors.primary)),
    ]),
    const SizedBox(height: 20),
    Semantics(label: 'Passo $step de $total', child: ExcludeSemantics(child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [for (var i = 1; i <= total; i++) Container(
        width: i == step ? 32 : 22, height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: i == step ? AppColors.primary : i < step ? const Color(0xFFBDB4ED) : AppColors.outline,
          borderRadius: BorderRadius.circular(20),
        ),
      )],
    ))),
  ]);
}
