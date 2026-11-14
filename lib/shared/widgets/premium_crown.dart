import 'package:flutter/material.dart';

/// Coroa que identifica uma criança Premium na área da família.
/// No plano gratuito (ou sem plano conhecido) não mostra nada.
/// Nunca usar na área da criança: a criança não vê planos nem ofertas.
class PremiumCrown extends StatelessWidget {
  const PremiumCrown({super.key, required this.isPremium, this.size = 20, this.leadingGap = 6});
  final bool isPremium;
  final double size;
  final double leadingGap;

  static const color = Color(0xFFE0A100);

  @override
  Widget build(BuildContext context) {
    if (!isPremium) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: leadingGap),
      child: Tooltip(
        message: 'Premium',
        child: Semantics(label: 'Plano Premium', child: Icon(Icons.workspace_premium_rounded, size: size, color: color)),
      ),
    );
  }
}
