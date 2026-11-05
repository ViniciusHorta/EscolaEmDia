import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/layout/onboarding_header.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../data/family_service.dart';
import '../domain/family_models.dart';
import 'widgets/avatar_selector.dart';
import 'widgets/school_year_selector.dart';

class ChildProfilePage extends StatefulWidget {
  const ChildProfilePage({super.key, required this.onSave, required this.onSaved, required this.onBack});
  final Future<ChildProfile> Function(ChildProfileDraft) onSave;
  final ValueChanged<ChildProfile> onSaved;
  final VoidCallback? onBack;

  @override
  State<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends State<ChildProfilePage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  String avatar = 'fox';
  int year = 3;
  String pin = '';
  String firstPin = '';
  String requestId = '';
  bool confirming = false;
  bool busy = false;
  int inputVersion = 0;
  String? error;

  @override
  void dispose() { name.dispose(); pin = ''; firstPin = ''; super.dispose(); }

  void back() {
    if (busy) return;
    if (confirming) {
      setState(() { confirming = false; firstPin = ''; pin = ''; error = null; inputVersion++; });
    } else { widget.onBack?.call(); }
  }

  Future<void> submit() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    if (!confirming) {
      if (!(form.currentState?.validate() ?? false)) return;
      if (pin.length != 4) {setState(() => error = 'Escolhe um PIN de 4 dígitos.'); return;}
      setState(() {firstPin = pin; pin = ''; confirming = true; inputVersion++; error = null; requestId = newRequestId();});
      return;
    }
    if (pin != firstPin) {
      setState(() {error = 'Os PINs não coincidem. Repete o PIN da criança.'; pin = ''; inputVersion++;});
      return;
    }
    setState(() {busy = true; error = null;});
    try {
      final child = await widget.onSave(ChildProfileDraft(requestId: requestId,
        displayName: name.text.trim(), schoolYear: year, avatarId: avatar, pin: pin));
      if (!mounted) return;
      firstPin = ''; pin = '';
      widget.onSaved(child);
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível guardar o perfil. Tenta novamente.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OnboardingHeader(title: 'Perfil do Educando', step: 3, section: 'Perfil', icon: Icons.face_rounded,
          onBack: busy || (!confirming && widget.onBack == null) ? null : back),
        const SizedBox(height: 28),
        const Center(child: AppBadge(label: 'Passo 3 de 4 • Perfil', icon: Icons.face_rounded)),
        const SizedBox(height: 20),
        Text(confirming ? 'Confirma o PIN da criança' : 'Um espaço só para a criança',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        Text(confirming ? 'Repete os mesmos 4 dígitos antes de guardar.' : 'Escolhe uma alcunha, um avatar amigo e o ano escolar.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (!confirming) AppCard(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(label: 'Como quer que a app lhe chame?', hint: 'Alcunha da criança', controller: name, enabled: !busy,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            validator: (value) => value == null || value.trim().isEmpty ? 'Indica a alcunha da criança.' : null),
          const SizedBox(height: 24),
          Text('Escolhe o avatar amigo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          AvatarSelector(value: avatar, enabled: !busy, onChanged: (value) => setState(() => avatar = value)),
          const SizedBox(height: 24),
          Text('Ano escolar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SchoolYearSelector(value: year, enabled: !busy, onChanged: (value) => setState(() => year = value)),
        ]))),
        if (confirming) AppCard(child: Row(children: [
          ExcludeSemantics(child: Text(ChildAvatars.emoji(avatar), style: const TextStyle(fontSize: 44))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.text.trim(), style: Theme.of(context).textTheme.titleLarge),
            Text('$year.º Ano • ${ChildAvatars.label(avatar)}'),
          ])),
        ])),
        const SizedBox(height: 24),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!confirming) ...[
            const Text('Um código simples para a criança entrar no seu próprio espaço.'),
            const SizedBox(height: 18),
          ],
          Center(child: AppPinInput(key: ValueKey(inputVersion),
            label: confirming ? 'Repetir PIN infantil' : 'PIN infantil (4 dígitos)',
            enabled: !busy, errorText: error,
            onChanged: (value) => setState(() {pin = value; error = null;}))),
        ])),
        const SizedBox(height: 28),
        AppButton(label: confirming ? 'Guardar perfil e avançar' : 'Confirmar PIN infantil',
          icon: Icons.arrow_forward_rounded, loading: busy, onPressed: busy || pin.length != 4 ? null : submit),
        const SizedBox(height: 16),
        const Text('Usa uma alcunha e escolhe um PIN diferente do PIN parental.',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 24),
      ]),
    ))),
  )));
}
