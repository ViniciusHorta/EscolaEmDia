import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/brand/app_logo.dart';

class FamilyBrandCard extends StatelessWidget {
  const FamilyBrandCard({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Column(children: [
      const AppLogo(size: 104, semanticLabel: null),
      const SizedBox(height: 20),
      Text('Escola em Dia', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.primary)),
      const SizedBox(height: 8),
      Text('Apoio escolar sereno em família', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
    ]),
  );
}
