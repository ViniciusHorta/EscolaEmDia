import 'package:flutter/foundation.dart';
import '../../../core/theme/area_palette.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/premium_crown.dart';
import '../domain/billing_models.dart';

/// Preço apresentado enquanto não há loja/Stripe ligados (Fase 3).
/// Nas fases de pagamento passa a vir do produto da loja.
const premiumPriceLabel = '3,99 €/mês';

/// Abre o pagamento; devolve uma mensagem de erro ou null quando o browser já foi redirecionado.
typedef PremiumSubscribe = Future<String?> Function();

/// Onde é feito o pagamento (muda o texto legal no fundo da oferta).
enum PremiumStore { stripe, googlePlay, appStore }

/// Web → Stripe; Android → Google Play; iOS → App Store.
PremiumStore get currentPremiumStore => kIsWeb ? PremiumStore.stripe
  : defaultTargetPlatform == TargetPlatform.android ? PremiumStore.googlePlay
  : defaultTargetPlatform == TargetPlatform.iOS ? PremiumStore.appStore
  : PremiumStore.stripe;

final termsUrl = Uri.parse('https://escolaemdia.me/termos-e-condicoes');
final privacyUrl = Uri.parse('https://escolaemdia.me/politica-de-privacidade');

String premiumPaymentNote(PremiumStore store) => switch (store) {
  PremiumStore.stripe => 'Pagamento seguro com Stripe. Vais sair da app para concluir. '
      'A assinatura renova-se todos os meses até a cancelares.',
  PremiumStore.googlePlay => 'Pagamento pela Google Play. A assinatura renova-se automaticamente todos os meses '
      'até a cancelares na Play Store.',
  // Texto exigido pela Apple para assinaturas com renovação automática.
  PremiumStore.appStore => 'Assinatura mensal com renovação automática. O pagamento é cobrado na tua conta Apple '
      'quando confirmas a compra e renova-se todos os meses, salvo se cancelares pelo menos 24 horas antes do fim '
      'do período atual. Podes gerir ou cancelar nas definições da tua conta Apple.',
};

/// Oferta Premium. SÓ para a área do responsável — nunca mostrar à criança.
/// Sem [onSubscribe] (ex.: app móvel antes das lojas) o botão explica que o pagamento chega em breve.
Future<void> showPremiumPaywall(BuildContext context, {required String childName, required PaywallReason reason,
    int? freeMaxQuestions, PremiumSubscribe? onSubscribe, PremiumStore? store}) =>
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true, backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
    builder: (context) => _PremiumPaywall(childName: childName, reason: reason, freeMaxQuestions: freeMaxQuestions,
      onSubscribe: onSubscribe, store: store ?? currentPremiumStore),
  );

class _PremiumPaywall extends StatefulWidget {
  const _PremiumPaywall({required this.childName, required this.reason, this.freeMaxQuestions, this.onSubscribe,
    this.store = PremiumStore.stripe});
  final PremiumStore store;
  final String childName;
  final PaywallReason reason;
  final int? freeMaxQuestions;
  final PremiumSubscribe? onSubscribe;
  @override
  State<_PremiumPaywall> createState() => _PremiumPaywallState();
}

class _PremiumPaywallState extends State<_PremiumPaywall> {
  bool busy = false;
  String? error;
  String get childName => widget.childName;
  PaywallReason get reason => widget.reason;
  int? get freeMaxQuestions => widget.freeMaxQuestions;

  Future<void> subscribe() async {
    final action = widget.onSubscribe;
    if (action == null) {
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Pagamento em breve'),
        content: const Text('A subscrição ainda não está disponível nesta versão. Em breve vais poder ativar o Premium aqui.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ok'))],
      ));
      return;
    }
    setState(() {busy = true; error = null;});
    final failure = await action();
    if (mounted) setState(() {busy = false; error = failure;});
  }

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
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Semantics(liveRegion: true,
        child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)))),
      AppButton(label: 'Ativar Premium para $childName', icon: Icons.workspace_premium_rounded, variant: AppButtonVariant.success,
        loading: busy, onPressed: busy ? null : subscribe),
      const SizedBox(height: 10),
      AppButton(label: 'Agora não', variant: AppButtonVariant.neutral, onPressed: busy ? null : () => Navigator.pop(context)),
      if (widget.onSubscribe != null) ...[
        Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(premiumPaymentNote(widget.store), textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted))),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton(onPressed: () => launchUrl(termsUrl, mode: LaunchMode.externalApplication),
            child: const Text('Termos de Utilização')),
          TextButton(onPressed: () => launchUrl(privacyUrl, mode: LaunchMode.externalApplication),
            child: const Text('Política de Privacidade')),
        ]),
      ],
    ]),
  ));
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
    CircleAvatar(radius: 18, backgroundColor: context.area.tint, child: Icon(icon, size: 20, color: context.area.primary)),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: AppColors.text))),
  ]));
}
