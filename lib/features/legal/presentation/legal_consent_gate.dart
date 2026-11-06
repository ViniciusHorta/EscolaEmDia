import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand/app_logo.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../data/legal_service.dart';
import '../domain/legal_models.dart';
import 'legal_document_page.dart';

/// Bloqueia o acesso enquanto o responsável não aceitar as versões em vigor dos documentos
/// legais que exigem aceite (primeiro acesso sem aceite no registo ou nova versão publicada).
class LegalConsentGate extends StatefulWidget {
  const LegalConsentGate({super.key, required this.service, required this.onSignOut, required this.child});
  final LegalService service;
  final Future<void> Function() onSignOut;
  final Widget child;

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> {
  late Future<LegalStatus> status;
  bool compliant = false;

  @override
  void initState() {
    super.initState();
    status = widget.service.status();
  }

  @override
  Widget build(BuildContext context) {
    if (compliant) return widget.child;
    return FutureBuilder<LegalStatus>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return AppPage(
            title: 'Vamos tentar outra vez?',
            subtitle: error is LegalException ? error.message : 'Não foi possível consultar os documentos legais.',
            children: [
              AppButton(label: 'Tentar novamente', onPressed: () => setState(() => status = widget.service.status())),
              const SizedBox(height: 16),
              AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary, onPressed: widget.onSignOut),
            ],
          );
        }
        if (!snapshot.hasData) return const AppSplash(message: 'A verificar os documentos legais');
        final value = snapshot.data!;
        if (value.compliant) return widget.child;
        return LegalConsentPage(
          key: ValueKey(value.pending.map((d) => d.id).join(',')),
          documents: value.pending,
          accepted: value.accepted,
          onAccept: (ids) async {
            final updated = await widget.service.accept(ids);
            if (!mounted) return;
            setState(() {
              compliant = updated.compliant;
              status = Future.value(updated);
            });
          },
          onReload: () => setState(() => status = widget.service.status()),
          onSignOut: widget.onSignOut,
        );
      },
    );
  }
}

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({
    super.key,
    required this.documents,
    required this.accepted,
    required this.onAccept,
    required this.onReload,
    required this.onSignOut,
  });
  final List<LegalDocument> documents;
  final List<LegalAcceptance> accepted;
  final Future<void> Function(List<String> ids) onAccept;
  final VoidCallback onReload;
  final Future<void> Function() onSignOut;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool agreed = false;
  bool showError = false;
  bool busy = false;
  String? feedback;
  bool outdated = false;

  /// Já aceitou alguma versão anterior: trata-se de uma atualização.
  bool get isUpdate => widget.documents.any((d) => widget.accepted.any((a) => a.kind == d.kind));

  Future<void> accept() async {
    if (busy) return;
    if (!agreed) { setState(() => showError = true); return; }
    setState(() { busy = true; feedback = null; });
    try {
      await widget.onAccept(widget.documents.map((d) => d.id).toList());
    } on LegalException catch (error) {
      if (mounted) setState(() { feedback = error.message; outdated = error.outdated; });
    } catch (_) {
      if (mounted) setState(() => feedback = 'Não foi possível registar o aceite. Tenta novamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    if (busy) return;
    setState(() => busy = true);
    try { await widget.onSignOut(); }
    catch (_) { if (mounted) setState(() => feedback = 'Não foi possível sair da conta. Tenta novamente.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.documents.map((d) => d.kind.label).join(' e ');
    return AppPage(
      title: isUpdate ? 'Atualizámos os nossos documentos' : 'Antes de continuar',
      subtitle: isUpdate
          ? 'Para continuares a usar a Escola em Dia, revê e aceita as novas versões: $names.'
          : 'Para usar a Escola em Dia, lê e aceita: $names.',
      children: [
        for (final document in widget.documents) ...[
          AppCard(
            onTap: busy ? null : () => LegalDocumentPage.open(context, document),
            semanticLabel: 'Ler ${document.kind.label}, versão ${document.version}',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.description_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(document.kind.label, style: Theme.of(context).textTheme.titleMedium)),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
              const SizedBox(height: 6),
              Text('Versão ${document.version} • em vigor desde ${formatLegalDate(document.publishedAt)}',
                style: const TextStyle(color: AppColors.muted)),
              if (document.changeSummary != null) ...[
                const SizedBox(height: 12),
                const Text('O que mudou', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(document.changeSummary!),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: agreed,
            isError: showError,
            semanticLabel: 'Li e aceito $names',
            onChanged: busy ? null : (value) => setState(() { agreed = value ?? false; showError = false; }),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Li e aceito ${widget.documents.length > 1 ? 'os documentos acima' : 'o documento acima'}.'),
          )),
        ]),
        if (showError) Semantics(liveRegion: true,
          child: const Text('Aceita os documentos para continuar.', style: TextStyle(color: AppColors.error))),
        if (feedback != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: AppCard(color: AppColors.softBlue, padding: const EdgeInsets.all(16),
            child: Text(feedback!))),
          if (outdated) TextButton(onPressed: widget.onReload, child: const Text('Ver a versão mais recente')),
        ],
        const SizedBox(height: 24),
        AppButton(label: 'Aceitar e continuar', icon: Icons.arrow_forward_rounded, loading: busy,
          onPressed: busy ? null : accept),
        const SizedBox(height: 16),
        AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary, onPressed: busy ? null : signOut),
      ],
    );
  }
}
