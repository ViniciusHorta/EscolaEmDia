import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/family_models.dart';

class AvatarSelector extends StatelessWidget {
  const AvatarSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = (constraints.maxWidth - 20) / 3;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final entry in ChildAvatars.choices.entries) SizedBox(width: width,
        child: Semantics(selected: value == entry.key, child: OutlinedButton(
          onPressed: enabled ? () => onChanged(entry.key) : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
            backgroundColor: value == entry.key ? AppColors.lavender : AppColors.surface,
            side: BorderSide(color: value == entry.key ? AppColors.primary : AppColors.outline,
              width: value == entry.key ? 2 : 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Column(children: [
            ExcludeSemantics(child: Text(entry.value.$2, style: const TextStyle(fontSize: 36))),
            const SizedBox(height: 8),
            Text(entry.value.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Icon(value == entry.key ? Icons.check_circle_rounded : Icons.circle_outlined, size: 18),
          ]),
        )),
      ),
    ]);
  });
}
