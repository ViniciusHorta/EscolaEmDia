import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';

class FamilyBrandCard extends StatelessWidget {
  const FamilyBrandCard({super.key});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Column(children: [
      ExcludeSemantics(child: SizedBox(
        width: 110,
        height: 100,
        child: Stack(children: [
          const Positioned(left: 6, bottom: 0, child: CircleAvatar(
            radius: 42,
            backgroundColor: AppColors.lavender,
            child: Icon(Icons.auto_stories_rounded, color: AppColors.primary, size: 42),
          )),
          Positioned(right: 0, top: 0, child: Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(color: Color(0xFFFBBF24), shape: BoxShape.circle),
            child: const Icon(Icons.star_rounded, color: AppColors.amber, size: 26),
          )),
        ]),
      )),
      const SizedBox(height: 20),
      Text('Escola em Dia', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.primary)),
      const SizedBox(height: 8),
      Text('Apoio escolar sereno em família', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
    ]),
  );
}
