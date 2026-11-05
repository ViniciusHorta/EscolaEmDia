import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class PinIndicators extends StatelessWidget {
  const PinIndicators(
      {super.key,
      required this.filled,
      this.length = 4,
      this.hasError = false,
      this.enabled = true});
  final int filled;
  final int length;
  final bool hasError;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(children: [
          for (var i = 0; i < length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
                child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: !enabled
                    ? AppColors.softBlue
                    : i < filled
                        ? AppColors.lavender
                        : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: hasError
                        ? AppColors.error
                        : i < filled
                            ? AppColors.primary
                            : AppColors.outline,
                    width: 2),
              ),
              alignment: Alignment.center,
              child: i < filled
                  ? const Icon(Icons.circle, size: 16, color: AppColors.primary)
                  : null,
            )),
          ],
        ]),
      );
}
