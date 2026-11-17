import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/area_palette.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand/app_logo.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../data/family_service.dart';
import '../domain/family_models.dart';

/// Convite para ser responsável de outra família (link do e-mail).
/// Aparece depois de entrar e desbloquear a área do responsável.
class AcceptInvitationPage extends StatefulWidget {
  const AcceptInvitationPage({
    super.key,
    required this.token,
    required this.service,
    required this.accountEmail,
    required this.onAccepted,
    required this.onDismiss,
  });

  final String token;
  final FamilyService service;
  final String accountEmail;
  final ValueChanged<String> onAccepted;
  final VoidCallback onDismiss;

  @override
  State<AcceptInvitationPage> createState() => _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends State<AcceptInvitationPage> {
  InvitationPreview? preview;
  bool accepting = false;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.service.previewInvitation(widget.token).then((value) {
      if (mounted) setState(() => preview = value);
    });
  }

  Future<void> accept() async {
    setState(() {accepting = true; error = null;});
    try {
      final familyId = await widget.service.acceptInvitation(widget.token);
      if (mounted) widget.onAccepted(familyId);
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p == null) return const AppSplash(message: 'A abrir o convite');
    final mismatch = p.pending && p.email.toLowerCase() != widget.accountEmail.toLowerCase();
    final (title, subtitle) = switch (p.status) {
      'pending' => ('Convite para a família',
          '${p.invitedBy ?? 'Um responsável'} convidou-te para seres responsável de uma família.'),
      'accepted' => ('Convite já aceite', 'Este convite já foi usado.'),
      'expired' => ('Convite expirado', 'Os convites são válidos durante 7 dias. Pede um novo convite.'),
      _ => ('Convite indisponível', 'Este convite foi cancelado ou substituído por um mais recente.'),
    };
    return AppPage(title: title, subtitle: subtitle, children: [
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(p.pending ? Icons.family_restroom_rounded : Icons.link_off_rounded, size: 56, color: context.area.primary),
        if (p.pending) ...[
          const SizedBox(height: 16),
          const Text('Como responsável, vais poder ver e gerir as crianças da família, preparar fichas e rever respostas. '
            'Todos os responsáveis têm as mesmas permissões.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('A tua conta só pode pertencer a uma família. Se já tiveres crianças noutra família, '
            'não vais conseguir aceitar.', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.muted)),
        ],
        if (mismatch) ...[
          const SizedBox(height: 16),
          Text('Este convite foi enviado para ${p.email}, mas entraste com ${widget.accountEmail}. '
            'Sai da conta e entra com o e-mail do convite.', textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error)),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(error!, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error))),
        ],
        const SizedBox(height: 24),
        if (p.pending && !mismatch) ...[
          AppButton(label: 'Aceitar convite', icon: Icons.check_rounded, loading: accepting,
            onPressed: accepting ? null : accept),
          const SizedBox(height: 12),
        ],
        AppButton(label: p.pending && !mismatch ? 'Agora não' : 'Continuar', variant: AppButtonVariant.secondary,
          onPressed: accepting ? null : widget.onDismiss),
      ])),
    ]);
  }
}
