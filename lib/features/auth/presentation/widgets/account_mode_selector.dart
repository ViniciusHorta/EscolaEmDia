import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

enum AccountMode { register, login }

class AccountModeSelector extends StatelessWidget {
  const AccountModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool enabled;
  final AccountMode value;
  final ValueChanged<AccountMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: AppColors.softBlue,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Row(children: [
      item(AccountMode.register, 'Criar conta', Icons.family_restroom_rounded),
      item(AccountMode.login, 'Já tenho conta', Icons.login_rounded),
    ]),
  );

  Widget item(AccountMode mode, String label, IconData icon) {
    final selected = value == mode;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: enabled ? () => onChanged(mode) : null,
          style: TextButton.styleFrom(
            backgroundColor: selected ? AppColors.surface : Colors.transparent,
            foregroundColor: selected ? AppColors.primary : AppColors.muted,
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            shape: const StadiumBorder(),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22),
            const SizedBox(width: 8),
            Flexible(child: Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }
}
