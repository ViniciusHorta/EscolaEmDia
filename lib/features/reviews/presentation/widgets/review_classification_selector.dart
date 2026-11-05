import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/parent_review_models.dart';

/// Aspeto de cada classificação (ícone, cores e descrição curta).
({IconData icon, Color ink, Color soft, Color shadow, String hint}) classificationStyle(ReviewClassification value) =>
    switch (value) {
      ReviewClassification.correct => (icon: Icons.check_rounded, ink: AppColors.success,
        soft: const Color(0xFFD1F5E6), shadow: const Color(0xFF10B981), hint: 'Totalidade'),
      ReviewClassification.partiallyCorrect => (icon: Icons.contrast_rounded, ink: const Color(0xFF8A5300),
        soft: AppColors.amberSoft, shadow: const Color(0xFFF59E0B), hint: 'Parte do raciocínio'),
      ReviewClassification.incorrect => (icon: Icons.close_rounded, ink: AppColors.error,
        soft: AppColors.coralSoft, shadow: const Color(0xFFFF7A59), hint: 'Precisa de rever'),
    };

/// Classificação rápida em blocos táteis (Stitch: Revisão de Resposta Aberta).
class ReviewClassificationSelector extends StatelessWidget {
  const ReviewClassificationSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final ReviewClassification? value;
  final ValueChanged<ReviewClassification> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = (constraints.maxWidth - 12) / 2;
    return Wrap(spacing: 12, runSpacing: 14, children: [
      for (final classification in ReviewClassification.values)
        SizedBox(width: width, child: _Tile(
          classification: classification,
          selected: value == classification,
          onTap: enabled && value != classification ? () => onChanged(classification) : null,
          enabled: enabled,
        )),
    ]);
  });
}

class _Tile extends StatelessWidget {
  const _Tile({required this.classification, required this.selected, required this.onTap, required this.enabled});
  final ReviewClassification classification;
  final bool selected, enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = classificationStyle(classification);
    return Semantics(
      button: true, selected: selected, inMutuallyExclusiveGroup: true, excludeSemantics: true,
      label: '${classification.label}. ${style.hint}',
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [BoxShadow(color: selected ? style.shadow : AppColors.blueBorder, offset: const Offset(0, 4))],
        ),
        child: Material(
          color: selected ? style.soft : AppColors.surface,
          shape: StadiumBorder(side: BorderSide(color: selected ? style.shadow : AppColors.blueBorder, width: selected ? 2 : 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Opacity(opacity: enabled || selected ? 1 : 0.5, child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
            child: Row(children: [
              CircleAvatar(radius: 21, backgroundColor: selected ? style.ink : style.soft,
                child: Icon(style.icon, color: selected ? Colors.white : style.ink, size: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(classification == ReviewClassification.partiallyCorrect ? 'Parcial' : classification.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? style.ink : AppColors.text)),
                Text(style.hint, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: selected ? style.ink : AppColors.muted)),
              ])),
            ]),
          ))),
        ),
      ),
    );
  }
}
