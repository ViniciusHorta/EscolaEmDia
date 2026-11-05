import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

class SchoolYearSelector extends StatelessWidget {
  const SchoolYearSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
    for (var year = 1; year <= 4; year++) ChoiceChip(
      label: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6), child: Text('$year.º Ano')),
      selected: value == year,
      selectedColor: AppColors.amberSoft,
      onSelected: enabled ? (_) => onChanged(year) : null,
    ),
  ]);
}
