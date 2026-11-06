import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/legal_models.dart';

/// Leitura de uma versão de um documento legal.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({super.key, required this.document, this.acceptedAt});
  final LegalDocument document;

  /// Quando indicado, mostra a data em que o responsável aceitou esta versão.
  final DateTime? acceptedAt;

  static Future<void> open(BuildContext context, LegalDocument document, {DateTime? acceptedAt}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LegalDocumentPage(document: document, acceptedAt: acceptedAt)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: Text(document.kind.label), backgroundColor: AppColors.background),
    body: SafeArea(child: SelectionArea(child: SingleChildScrollView(
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(document.title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Versão ${document.version} • em vigor desde ${formatLegalDate(document.publishedAt)}',
              style: const TextStyle(color: AppColors.muted)),
            if (acceptedAt != null) ...[
              const SizedBox(height: 4),
              Text('Aceite por ti em ${formatLegalDate(acceptedAt!)}', style: const TextStyle(color: AppColors.success)),
            ],
            const SizedBox(height: 24),
            ...LegalMarkdown.build(context, document.content),
          ]),
        ),
      )),
    ))),
  );
}

/// Subconjunto de Markdown usado nos documentos legais: títulos (#, ##, ###), parágrafos,
/// listas (- ou *) e **negrito**. Evita uma dependência externa só para estes textos.
abstract final class LegalMarkdown {
  static List<Widget> build(BuildContext context, String source) {
    final theme = Theme.of(context).textTheme;
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      widgets.add(Padding(padding: const EdgeInsets.only(bottom: 14),
        child: Text.rich(TextSpan(children: inline(paragraph.join(' '))), style: theme.bodyLarge)));
      paragraph.clear();
    }

    for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
      if (line.trim().isEmpty) {
        flush();
      } else if (heading != null) {
        flush();
        final level = heading.group(1)!.length;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: level == 1 ? 8 : 16, bottom: 8),
          child: Semantics(header: true, child: Text(heading.group(2)!,
            style: level == 1 ? theme.headlineSmall : level == 2 ? theme.titleLarge : theme.titleMedium)),
        ));
      } else if (bullet != null) {
        flush();
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: theme.bodyLarge),
            Expanded(child: Text.rich(TextSpan(children: inline(bullet.group(1)!)), style: theme.bodyLarge)),
          ]),
        ));
      } else {
        paragraph.add(line.trim());
      }
    }
    flush();
    return widgets;
  }

  static List<TextSpan> inline(String text) {
    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(text: parts[i],
        style: i.isOdd && i < parts.length - 1 ? const TextStyle(fontWeight: FontWeight.w700) : null));
    }
    return spans;
  }
}
