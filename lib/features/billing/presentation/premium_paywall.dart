import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/premium_crown.dart';
import '../domain/billing_models.dart';

/// Preço apresentado enquanto não há loja/Stripe ligados (Fase 3).
/// Nas fases de pagamento passa a vir do produto da loja.
const premiumPriceLabel = '3,99 €/mês';

/// Oferta Premium. SÓ para a área do responsável — nunca mostrar à criança.
Future<void> showPremiumPaywall(BuildContext context, {required String childName, required PaywallReason reason, int? freeMaxQuestions}) =>
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true, backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
    builder: (context) => _PremiumPaywall(childName: childName, reason: reason, freeMaxQuestions: freeMaxQuestions),
  );

class _PremiumPaywall extends StatelessWidget {
  const _PremiumPaywall({required this.childName, required this.reason, this.freeMaxQuestions});
  final String childName;
  final PaywallReason reason;
  final int? freeMaxQuestions;

  String get headline => switch (reason) {
    PaywallReason.dailyLimit => '$childName já recebeu a ficha de hoje',
    PaywallReason.premiumWorksheet => 'Esta ficha é Premium',
    PaywallReason.locked => '$childName precisa do Premium',
    PaywallReason.general => 'Premium para $childName',
  };
  String get explanation => switch (reason) {
    PaywallReason.dailyLimit => 'No plano gratuito cada criança recebe 1 ficha por dia. Amanhã podes preparar outra — ou ativa o Premium para continuar já hoje.',
    PaywallReason.premiumWorksheet => 'O plano gratuito inclui as fichas Free. Com o Premium, $childName tem acesso a todo o catálogo.',
    PaywallReason.locked => 'A vaga gratuita da família já está ocupada por outra criança. Ativa o Premium para $childName receber e fazer fichas.',
    PaywallReason.general => 'Desbloqueia todas as fichas e pratica sem limites diários.',
  };

  @override
  Widget build(BuildContext context) => SafeArea(child: SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(child: Icon(Icons.workspace_premium_rounded, size: 56, color: PremiumCrown.color)),
      const SizedBox(height: 12),
      Semantics(header: true, child: Text(headline, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.text))),
      const SizedBox(height: 10),
      Text(explanation, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.muted)),
      const SizedBox(height: 22),
      _Benefit(icon: Icons.all_inclusive_rounded, text: 'Fichas sem limite diário'),
      const _Benefit(icon: Icons.auto_stories_rounded, text: 'Catálogo completo, incluindo fichas Premium'),
      _Benefit(icon: Icons.format_list_numbered_rounded,
        text: freeMaxQuestions == null ? 'Fichas mais longas' : 'Fichas com mais de $freeMaxQuestions perguntas'),
      const _Benefit(icon: Icons.replay_rounded, text: 'Repetir fichas sempre que quiser'),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CC), borderRadius: BorderRadius.circular(AppRadii.input)),
        child: Column(children: [
          const Text(premiumPriceLabel, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.amber)),
          Text('por criança • cancela quando quiseres', style: TextStyle(fontSize: 14, color: AppColors.amber.withValues(alpha: 0.9))),
        ]),
      ),
      const SizedBox(height: 18),
      AppButton(label: 'Ativar Premium para $childName', icon: Icons.workspace_premium_rounded, variant: AppButtonVariant.success,
        onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Pagamento em breve'),
          content: const Text('A subscrição ainda não está disponível nesta versão. Em breve vais poder ativar o Premium aqui.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ok'))],
        ))),
      const SizedBox(height: 10),
      AppButton(label: 'Agora não', variant: AppButtonVariant.neutral, onPressed: () => Navigator.pop(context)),
    ]),
  ));
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
    CircleAvatar(radius: 18, backgroundColor: AppColors.lavender, child: Icon(icon, size: 20, color: AppColors.primary)),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: AppColors.text))),
  ]));
}
