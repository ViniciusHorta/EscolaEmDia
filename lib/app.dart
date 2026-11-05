import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/component_gallery/component_gallery_page.dart';

class EscolaEmDiaApp extends StatelessWidget {
  const EscolaEmDiaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Escola em Dia',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('pt', 'PT'),
        supportedLocales: const [Locale('pt', 'PT')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AuthGate(),
        routes: {
          '/components': (_) => const ComponentGalleryPage(),
        },
      );
}
