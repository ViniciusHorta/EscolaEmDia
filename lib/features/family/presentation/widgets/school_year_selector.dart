import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

/// Escolha do ano escolar: botões para o ciclo (1.º, 2.º ou 3.º) e, por baixo, as linhas
/// táteis com os anos desse ciclo e a faixa etária habitual.
class SchoolYearSelector extends StatefulWidget {
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

  /// Ciclo a que pertence [year] (o 1.º se o ano for desconhecido).
  static String cycleOf(int year) =>
    cycles.entries.firstWhere((c) => c.value.contains(year), orElse: () => cycles.entries.first).key;

  @override
  State<SchoolYearSelector> createState() => _SchoolYearSelectorState();
}

class _SchoolYearSelectorState extends State<SchoolYearSelector> {
  late String cycle = SchoolYearSelector.cycleOf(widget.value);

  @override
  void didUpdateWidget(SchoolYearSelector old) {
    super.didUpdateWidget(old);
    // Se o ano mudar por fora (ex.: perfil carregado), mostra o ciclo desse ano.
    if (old.value != widget.value) cycle = SchoolYearSelector.cycleOf(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final years = SchoolYearSelector.cycles[cycle]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(container: true, label: 'Ciclo do Ensino Básico', child: Row(children: [
        for (final entry in SchoolYearSelector.cycles.entries) ...[
          if (entry.key != SchoolYearSelector.cycles.keys.first) const SizedBox(width: 8),
          Expanded(child: _CycleButton(label: entry.key,
            years: '${entry.value.first}.º–${entry.value.last}.º ano',
            selected: cycle == entry.key,
            onTap: widget.enabled ? () => setState(() => cycle = entry.key) : null)),
        ],
      ])),
      const SizedBox(height: 14),
      for (final year in years) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _YearRow(year: year, ages: SchoolYearSelector.ages[year]!, selected: widget.value == year,
          onTap: widget.enabled ? () => widget.onChanged(year) : null),
      ),
    ]);
  }
}

class _CycleButton extends StatelessWidget {
  const _CycleButton({required this.label, required this.years, required this.selected, required this.onTap});
  final String label, years;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, selected: selected, inMutuallyExclusiveGroup: true, excludeSemantics: true,
    label: '$label, $years',
    child: Material(
      color: selected ? AppColors.primary : AppColors.softBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.blueBorder, width: selected ? 2 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.text)),
            const SizedBox(height: 2),
            Text(years, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: selected ? Colors.white.withValues(alpha: 0.9) : AppColors.muted)),
          ]),
        ),
      )),
    ),
  );
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
