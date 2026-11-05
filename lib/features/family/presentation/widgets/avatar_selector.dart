import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../domain/family_models.dart';

/// Grelha de avatares (Stitch: Perfil do Educando & PIN Infantil).
class AvatarSelector extends StatelessWidget {
  const AvatarSelector({super.key, required this.value, required this.onChanged, this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    const gap = 12.0;
    final width = (constraints.maxWidth - gap * 2) / 3;
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final entry in ChildAvatars.choices.entries) SizedBox(width: width, child: _AvatarTile(
        label: entry.value.$1, emoji: entry.value.$2, selected: value == entry.key,
        onTap: enabled ? () => onChanged(entry.key) : null,
      )),
    ]);
  });
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.label, required this.emoji, required this.selected, required this.onTap});
  final String label, emoji;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true, selected: selected, inMutuallyExclusiveGroup: true, excludeSemantics: true, label: 'Avatar $label',
    child: Material(
      color: selected ? AppColors.lavender : AppColors.softBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.blueBorder, width: selected ? 2.5 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        child: Column(children: [
          SizedBox(width: 72, height: 66, child: Stack(children: [
            Positioned(left: 4, top: 0, child: Container(
              width: 62, height: 62, alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                border: Border.all(color: selected ? const Color(0xFFC7BFFF) : Colors.white, width: 3)),
              child: Text(emoji, style: const TextStyle(fontSize: 34)),
            )),
            if (selected) const Positioned(right: 0, top: 0, child: CircleAvatar(radius: 11,
              backgroundColor: AppColors.primary, child: Icon(Icons.check_rounded, size: 15, color: Colors.white))),
          ])),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.text)),
        ]),
      )),
    ),
  );
}
