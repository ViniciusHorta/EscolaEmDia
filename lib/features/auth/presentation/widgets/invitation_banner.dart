import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../family/data/family_service.dart';
import '../../../family/data/pending_invitation_store.dart';
import '../../../family/domain/family_models.dart';
import '../../../../shared/widgets/app_card.dart';

/// No ecrã de entrada: «Foste convidado…» quando se chega pelo link do convite.
/// [onInvitation] recebe o convite para pré-preencher o e-mail e escolher Entrar/Criar conta.
class InvitationBanner extends StatefulWidget {
  const InvitationBanner({super.key, required this.client, required this.onInvitation});
  final SupabaseClient client;
  final ValueChanged<InvitationPreview> onInvitation;

  @override
  State<InvitationBanner> createState() => _InvitationBannerState();
}

class _InvitationBannerState extends State<InvitationBanner> {
  InvitationPreview? preview;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final token = await PendingInvitationStore.read();
    if (token == null) return;
    final result = await FamilyService(widget.client).previewInvitation(token);
    if (!mounted || !result.pending) return;
    setState(() => preview = result);
    widget.onInvitation(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: AppCard(color: AppColors.softBlue, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.family_restroom_rounded, color: AppColors.primary, size: 32),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tens um convite para uma família', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(p.accountExists
            ? '${p.invitedBy ?? 'Um responsável'} convidou-te. Entra com ${p.email} para aceitar.'
            : '${p.invitedBy ?? 'Um responsável'} convidou-te. Cria a tua conta com ${p.email} para aceitar.'),
        ])),
      ])),
    );
  }
}
