import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/widgets/app_card.dart';
import 'family_brand_card.dart';

/// Moldura comum dos ecrãs de autenticação: cartão da marca, cartão principal
/// e nota de rodapé, centrados com a largura do ecrã de conta familiar.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child, this.footer = const []});
  final Widget child;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FamilyBrandCard(),
            const SizedBox(height: 24),
            AppCard(child: child),
            const SizedBox(height: 24),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.muted, size: 20),
              SizedBox(width: 10),
              Flexible(child: Text('Apoio escolar pensado para as famílias em Portugal',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13))),
            ]),
            ...footer,
            const SizedBox(height: 24),
          ]),
        ),
      )),
    )),
  );
}

/// Cabeçalho dentro do cartão: ícone em bolha lavanda, título e descrição.
class AuthCardHeader extends StatelessWidget {
  const AuthCardHeader({super.key, required this.icon, required this.title, required this.subtitle, this.onBack});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      if (onBack != null)
        IconButton.filledTonal(onPressed: onBack, tooltip: 'Voltar', icon: const Icon(Icons.arrow_back_rounded))
      else
        const SizedBox(width: 48),
      const Spacer(),
      ExcludeSemantics(child: CircleAvatar(
        radius: 32,
        backgroundColor: AppColors.lavender,
        child: Icon(icon, color: AppColors.primary, size: 32),
      )),
      const Spacer(),
      const SizedBox(width: 48),
    ]),
    const SizedBox(height: 20),
    Semantics(header: true, child: Text(title, textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall)),
    const SizedBox(height: 10),
    Text(subtitle, textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
  ]);
}

/// Mensagem de estado anunciada a leitores de ecrã.
class AuthFeedback extends StatelessWidget {
  const AuthFeedback(this.message, {super.key, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(liveRegion: true, child: AppCard(
    color: error ? AppColors.coralSoft : AppColors.softBlue,
    padding: const EdgeInsets.all(16),
    child: Text(message),
  ));
}
