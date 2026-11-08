import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Anos do 1.º, 2.º e 3.º Ciclos com a faixa etária habitual, em linhas táteis agrupadas por ciclo.
class SchoolYearSelector extends StatelessWidget {
  const SchoolYearSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  static const ages = {
    1: '6–7 anos', 2: '7–8 anos', 3: '8–9 anos', 4: '9–10 anos',
    5: '10–11 anos', 6: '11–12 anos',
    7: '12–13 anos', 8: '13–14 anos', 9: '14–15 anos',
  };

  /// Ciclos do ensino básico suportados e respetivos anos.
  static const cycles = <String, List<int>>{
    '1.º Ciclo': [1, 2, 3, 4],
    '2.º Ciclo': [5, 6],
    '3.º Ciclo': [7, 8, 9],
  };

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final cycle in cycles.entries) ...[
      Padding(
        padding: EdgeInsets.only(bottom: 8, top: cycle.key == cycles.keys.first ? 0 : 8),
        child: Semantics(header: true, child: Text(cycle.key,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.3))),
      ),
      for (final year in cycle.value) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _YearRow(year: year, ages: ages[year]!, selected: value == year,
          onTap: enabled ? () => onChanged(year) : null),
      ),
    ],
  ]);
}

class _YearRow extends StatelessWidget {
  const _YearRow({required this.year, required this.ages, required this.selected, required this.onTap});
  final int year;
  final String ages;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, selected: selected, inMutuallyExclusiveGroup: true, excludeSemantics: true,
    label: '$year.º Ano de Escolaridade, $ages',
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: selected ? const Color(0xFFF59E0B) : AppColors.blueBorder, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: selected ? const Color(0xFFFFE7C2) : AppColors.softBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: selected ? const Color(0xFFF59E0B) : AppColors.blueBorder, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(children: [
            CircleAvatar(radius: 24, backgroundColor: selected ? const Color(0xFFFEA619) : AppColors.blueBorder,
              child: Text('$year.º', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.text))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$year.º Ano de Escolaridade', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: selected ? Colors.white.withValues(alpha: 0.7) : AppColors.lavender,
                  borderRadius: BorderRadius.circular(AppRadii.pill)),
                child: Text(ages, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
              ),
            ])),
            selected
              ? const CircleAvatar(radius: 15, backgroundColor: Color(0xFF8A5300), child: Icon(Icons.check_rounded, size: 20, color: Colors.white))
              : Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: AppColors.outline, width: 2))),
          ]),
        )),
      ),
    ),
  );
}
