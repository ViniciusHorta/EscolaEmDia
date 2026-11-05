import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

class AppBadge extends StatelessWidget {
  const AppBadge(
      {super.key,
      required this.label,
      this.icon,
      this.color = AppColors.primary,
      this.background = AppColors.lavender});
  final String label;
  final IconData? icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: background,
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
