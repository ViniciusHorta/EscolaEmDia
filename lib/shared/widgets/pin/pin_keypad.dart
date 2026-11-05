import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

class PinKeypad extends StatelessWidget {
  const PinKeypad(
      {super.key,
      required this.onDigit,
      required this.onDelete,
      required this.onClear,
      this.enabled = true});
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 20) / 3;
        Widget key(String label, VoidCallback action, {IconData? icon}) =>
            SizedBox(
              width: width,
              height: 60,
              child: OutlinedButton(
                onPressed: enabled ? action : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  backgroundColor: AppColors.softBlue,
                  side: const BorderSide(color: AppColors.blueBorder, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: EdgeInsets.zero,
                ),
                child: icon != null
                    ? Icon(icon, semanticLabel: label)
                    : Text(label,
                        style: TextStyle(
                            fontSize: label.length == 1 ? 24 : 13,
                            fontWeight: FontWeight.w700)),
              ),
            );
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 1; i <= 9; i++) key('$i', () => onDigit('$i')),
          key('Limpar PIN', onClear, icon: Icons.clear_all_rounded),
          key('0', () => onDigit('0')),
          key('Apagar último dígito', onDelete, icon: Icons.backspace_outlined),
        ]);
      });
}
