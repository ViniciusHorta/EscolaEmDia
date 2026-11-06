import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/legal_service.dart';
import '../domain/legal_models.dart';
import 'legal_document_page.dart';

/// Área do responsável: versões em vigor e versões aceites por ele.
class LegalDocumentsPage extends StatefulWidget {
  const LegalDocumentsPage({super.key, required this.service});
  final LegalService service;

  static Future<void> open(BuildContext context, LegalService service) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => LegalDocumentsPage(service: service)));

  @override
  State<LegalDocumentsPage> createState() => _LegalDocumentsPageState();
}

class _LegalDocumentsPageState extends State<LegalDocumentsPage> {
  late Future<LegalStatus> status = widget.service.status();
  String? openingError;

  Future<void> openAccepted(LegalAcceptance acceptance) async {
    setState(() => openingError = null);
    try {
      final document = await widget.service.document(acceptance.documentId);
      if (mounted) await LegalDocumentPage.open(context, document, acceptedAt: acceptance.acceptedAt);
    } on LegalException catch (error) {
      if (mounted) setState(() => openingError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Documentos legais'), backgroundColor: AppColors.background),
    body: SafeArea(child: FutureBuilder<LegalStatus>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(error is LegalException ? error.message : 'Não foi possível carregar os documentos legais.',
              textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(label: 'Tentar novamente', expand: false,
              onPressed: () => setState(() => status = widget.service.status())),
          ])));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final value = snapshot.data!;
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final document in value.current) ...[
            _DocumentCard(
              document: document,
              accepted: value.accepted.where((a) => a.kind == document.kind).toList(),
              onOpenCurrent: () {
                final match = value.accepted.where((a) => a.documentId == document.id).firstOrNull;
                LegalDocumentPage.open(context, document, acceptedAt: match?.acceptedAt);
              },
              onOpenAccepted: openAccepted,
            ),
            const SizedBox(height: 16),
          ],
          if (openingError != null) Text(openingError!, style: const TextStyle(color: AppColors.error)),
        ]);
      },
    )),
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.accepted, required this.onOpenCurrent, required this.onOpenAccepted});
  final LegalDocument document;
  final List<LegalAcceptance> accepted;
  final VoidCallback onOpenCurrent;
  final ValueChanged<LegalAcceptance> onOpenAccepted;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(document.kind.label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Versão em vigor: ${document.version} (desde ${formatLegalDate(document.publishedAt)})',
        style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: onOpenCurrent, icon: const Icon(Icons.description_outlined),
        label: const Text('Ler versão em vigor')),
      if (accepted.isNotEmpty) ...[
        const Divider(),
        const Text('Os teus aceites', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final acceptance in accepted)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_outlined, color: AppColors.success),
            title: Text('Versão ${acceptance.version}'),
            subtitle: Text('Aceite em ${formatLegalDate(acceptance.acceptedAt)}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onOpenAccepted(acceptance),
          ),
      ],
    ]),
  );
}
