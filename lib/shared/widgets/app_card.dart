import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(AppSpacing.lg),
      this.color = AppColors.surface,
      this.selected = false,
      this.onTap,
      this.semanticLabel});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        selected: onTap != null ? selected : null,
        button: onTap != null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Material(
            color: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(
                  color: selected ? AppColors.primary : AppColors.lavender,
                  width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      );
}
