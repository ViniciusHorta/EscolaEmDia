import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../brand/app_logo.dart';

class AppPage extends StatelessWidget {
  const AppPage(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: SingleChildScrollView(
                child: Center(
                    child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.maxWidth),
          child: Padding(
            padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const AppLogo(size: 50, semanticLabel: null),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('Escola em Dia',
                            style: Theme.of(context).textTheme.titleLarge)),
                  ]),
                  const SizedBox(height: 36),
                  Text(title,
                      style: MediaQuery.sizeOf(context).width < 640
                          ? Theme.of(context).textTheme.headlineMedium
                          : Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 10),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 32),
                  ...children,
                  const SizedBox(height: 32),
                ]),
          ),
        )))),
      );
}
