import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';

/// Logo oficial da Escola em Dia (assets/branding/logo.png).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.semanticLabel = 'Escola em Dia'});
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      );
}

/// Ecrã de arranque em Flutter: continua o splash nativo (mesmo fundo creme e
/// logo de 120dp) enquanto a sessão e os dados iniciais carregam.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key, this.message = 'A abrir a tua sessão'});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Semantics(
            label: message,
            liveRegion: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppLogo(size: 120, semanticLabel: null),
              const SizedBox(height: 28),
              const ExcludeSemantics(
                child: Text('Escola em Dia',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text)),
              ),
              const SizedBox(height: 6),
              const ExcludeSemantics(
                child: Text('Apoio escolar sereno em família',
                    style: TextStyle(fontSize: 15, color: AppColors.muted)),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
              ),
            ]),
          ),
        ),
      );
}
