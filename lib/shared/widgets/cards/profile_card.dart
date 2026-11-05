import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../app_card.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard(
      {super.key,
      required this.name,
      required this.schoolYear,
      required this.avatar,
      required this.onTap,
      this.selected = false});
  final String name;
  final int schoolYear;
  final IconData avatar;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => AppCard(
        selected: selected,
        onTap: onTap,
        child: Column(children: [
          CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.lavender,
              child: Icon(avatar, color: AppColors.primary, size: 38)),
          const SizedBox(height: 14),
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('$schoolYear.º Ano',
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.outline,
              semanticLabel: selected ? 'Selecionado' : 'Selecionar'),
        ]),
      );
}
