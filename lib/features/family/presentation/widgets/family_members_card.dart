import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/area_palette.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../data/family_service.dart';
import '../../domain/family_models.dart';

/// Separador Família → «Responsáveis»: lista, convidar por e-mail, cancelar convite,
/// remover outro responsável ou sair da família.
class FamilyMembersCard extends StatefulWidget {
  const FamilyMembersCard({super.key, required this.familyId, required this.service, required this.onLeft, this.busy = false});
  final String familyId;
  final FamilyService service;
  /// O próprio adulto saiu da família.
  final VoidCallback onLeft;
  final bool busy;

  @override
  State<FamilyMembersCard> createState() => _FamilyMembersCardState();
}

class _FamilyMembersCardState extends State<FamilyMembersCard> {
  FamilyMembers? data;
  String? error;
  bool working = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final result = await widget.service.listMembers(widget.familyId);
      if (mounted) setState(() => data = result);
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    }
  }

  void snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Devolve true quando o pedido correu bem.
  Future<bool> run(Future<void> Function() action, {String? success, bool reload = true}) async {
    setState(() => working = true);
    try {
      await action();
      if (success != null && mounted) snack(success);
      if (reload && mounted) await load();
      return true;
    } on FamilyException catch (failure) {
      if (mounted) snack(failure.message);
      return false;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<bool> confirm(String title, String body, String action) async => await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(dialog, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error), child: Text(action)),
      ],
    ),
  ) ?? false;

  Future<void> invite() async {
    final email = await showDialog<String>(context: context, builder: (_) => const _InviteDialog());
    if (email == null || !mounted) return;
    await run(() => widget.service.inviteAdult(widget.familyId, email),
      success: 'Convite enviado para $email.');
  }

  Future<void> resend(FamilyInvitation invitation) async => run(
    () => widget.service.inviteAdult(widget.familyId, invitation.email),
    success: 'Convite reenviado para ${invitation.email}.');

  Future<void> cancel(FamilyInvitation invitation) async {
    if (!await confirm('Cancelar convite?', 'O link enviado para ${invitation.email} deixa de funcionar.', 'Cancelar convite')) {
      return;
    }
    await run(() => widget.service.cancelInvitation(widget.familyId, invitation.id), success: 'Convite cancelado.');
  }

  Future<void> remove(FamilyMember member) async {
    if (member.isMe) {
      final leave = await confirm('Sair da família?',
        'Deixas de ter acesso às crianças desta família. Os outros responsáveis continuam com acesso.', 'Sair');
      if (leave && await run(() => widget.service.removeMember(widget.familyId, member.adultUserId), reload: false) && mounted) {
        widget.onLeft();
      }
      return;
    }
    if (!await confirm('Remover responsável?', '${member.email} deixa de ter acesso às crianças desta família.', 'Remover')) {
      return;
    }
    await run(() => widget.service.removeMember(widget.familyId, member.adultUserId), success: 'Responsável removido.');
  }

  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    final d = data;
    final disabled = widget.busy || working;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.supervisor_account_rounded, color: context.area.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text('Responsáveis', style: Theme.of(context).textTheme.titleLarge)),
        if (working) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 6),
      const Text('Adultos com acesso a esta família. Todos têm as mesmas permissões.',
        style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      if (error != null) ...[
        Text(error!, style: const TextStyle(color: AppColors.error)),
        TextButton(onPressed: load, child: const Text('Tentar novamente')),
      ] else if (d == null)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else ...[
        for (final m in d.members) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(backgroundColor: context.area.tint,
            child: Icon(Icons.person_rounded, color: context.area.primary)),
          title: Text(m.isMe ? '${m.email} (tu)' : m.email, overflow: TextOverflow.ellipsis),
          subtitle: Text('Responsável desde ${date(m.joinedAt)}'),
          trailing: d.members.length < 2 ? null : PopupMenuButton<String>(
            tooltip: 'Opções de ${m.email}',
            enabled: !disabled,
            onSelected: (_) => remove(m),
            itemBuilder: (_) => [PopupMenuItem(value: 'remove', child: ListTile(
              leading: Icon(m.isMe ? Icons.logout_rounded : Icons.person_remove_rounded, color: AppColors.error),
              title: Text(m.isMe ? 'Sair da família' : 'Remover'),
            ))],
          ),
        ),
        for (final i in d.invitations) ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(backgroundColor: AppColors.amberSoft,
            child: Icon(Icons.mail_outline_rounded, color: AppColors.amber)),
          title: Text(i.email, overflow: TextOverflow.ellipsis),
          subtitle: Text(i.expired ? 'Convite expirado' : 'Convite pendente • válido até ${date(i.expiresAt)}',
            style: TextStyle(color: i.expired ? AppColors.error : AppColors.muted)),
          trailing: PopupMenuButton<String>(
            tooltip: 'Opções do convite para ${i.email}',
            enabled: !disabled,
            onSelected: (action) => action == 'resend' ? resend(i) : cancel(i),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'resend', child: ListTile(leading: Icon(Icons.send_rounded), title: Text('Reenviar'))),
              PopupMenuItem(value: 'cancel', child: ListTile(
                leading: Icon(Icons.close_rounded, color: AppColors.error), title: Text('Cancelar convite'))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppButton(label: 'Convidar responsável', icon: Icons.person_add_alt_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: disabled || !d.canInvite ? null : invite),
        if (!d.canInvite) const Padding(padding: EdgeInsets.only(top: 8),
          child: Text('Uma família pode ter até ${FamilyMembers.limit} responsáveis, incluindo convites pendentes.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted))),
      ],
    ]));
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();

  @override
  void dispose() {email.dispose(); super.dispose();}

  void submit() {
    if (form.currentState?.validate() ?? false) Navigator.pop(context, email.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Convidar responsável'),
    content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Enviamos um convite por e-mail, válido durante 7 dias. '
        'A pessoa tem de entrar ou criar conta com esse e-mail para aceitar.'),
      const SizedBox(height: 16),
      AppTextField(
        label: 'E-mail do responsável', hint: 'exemplo@email.pt', controller: email,
        keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
        prefixIcon: Icons.mail_outline_rounded, textInputAction: TextInputAction.send,
        onSubmitted: (_) => submit(),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Indica o e-mail.';
          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) return 'Indica um endereço de e-mail válido.';
          return null;
        },
      ),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: submit, child: const Text('Enviar convite')),
    ],
  );
}
