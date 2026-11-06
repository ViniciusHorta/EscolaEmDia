import 'package:flutter/material.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/layout/app_page.dart';

class RepeatWorksheetConfirmation extends StatelessWidget {
  const RepeatWorksheetConfirmation({super.key, required this.title, required this.onConfirm,
    required this.onCancel, required this.onParents});
  final String title;
  final VoidCallback onConfirm, onCancel, onParents;
  @override
  Widget build(BuildContext context) => PopScope(canPop: false, child: AppPage(
    title: 'Vamos fazer outra vez?', subtitle: title, children: [
      const AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Vais começar uma nova tentativa com as respostas em branco.'),
        SizedBox(height: 12), Text('As respostas e correções das tentativas anteriores ficam guardadas.'),
        SizedBox(height: 12), Text('Se já começaste outra tentativa noutro dispositivo, vamos continuar essa tentativa.'),
      ])),
      const SizedBox(height: 24), AppButton(label: 'Começar nova tentativa', icon: Icons.replay_rounded, onPressed: onConfirm),
      const SizedBox(height: 16), AppButton(label: 'Agora não', variant: AppButtonVariant.secondary, onPressed: onCancel),
      const SizedBox(height: 16), TextButton.icon(onPressed: onParents, icon: const Icon(Icons.lock_outline_rounded), label: const Text('Área do responsável')),
    ],
  ));
}
