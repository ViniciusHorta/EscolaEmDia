import 'package:flutter/material.dart';
import '../../core/theme/area_palette.dart';
import '../../core/theme/app_tokens.dart';

class AppBadge extends StatelessWidget {
  const AppBadge(
      {super.key,
      required this.label,
      this.icon,
      this.color,
      this.background});
  final String label;
  final IconData? icon;
  /// Por omissão, a cor principal da área atual.
  final Color? color;
  /// Por omissão, o tom suave da área atual.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.area.primary;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: background ?? context.area.tint,
            borderRadius: BorderRadius.circular(AppRadii.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6)
          ],
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]),
      );
  }
}
