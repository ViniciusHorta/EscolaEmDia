import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/request_id.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/layout/onboarding_header.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../data/family_service.dart';
import '../domain/family_models.dart';
import 'widgets/avatar_selector.dart';
import 'widgets/school_year_selector.dart';

class ChildProfilePage extends StatefulWidget {
  const ChildProfilePage({super.key, required this.onSave, required this.onSaved, required this.onBack})
    : initial = null, onUpdate = null;

  /// Edição de um perfil existente: alcunha, avatar e ano pré-preenchidos; o PIN só
  /// muda se o adulto escolher «Alterar PIN».
  const ChildProfilePage.edit({super.key, required ChildProfile child, required Future<ChildProfile> Function(ChildProfileUpdate) this.onUpdate,
    required this.onSaved, required this.onBack})
    : initial = child, onSave = null;

  final Future<ChildProfile> Function(ChildProfileDraft)? onSave;
  final Future<ChildProfile> Function(ChildProfileUpdate)? onUpdate;
  final ChildProfile? initial;
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
  bool changePin = false;

  bool get isEdit => widget.initial != null;
  bool get needsPin => !isEdit || changePin;

  @override
  void initState() {
    super.initState();
    final child = widget.initial;
    if (child != null) {name.text = child.displayName; avatar = child.avatarId; year = child.schoolYear;}
  }

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
      if (!needsPin) {await persist(null); return;}
      if (pin.length != 4) {setState(() => error = 'Escolhe um PIN de 4 dígitos.'); return;}
      setState(() {firstPin = pin; pin = ''; confirming = true; inputVersion++; error = null; requestId = newRequestId();});
      return;
    }
    if (pin != firstPin) {
      setState(() {error = 'Os PINs não coincidem. Repete o PIN da criança.'; pin = ''; inputVersion++;});
      return;
    }
    await persist(pin);
  }

  Future<void> persist(String? newPin) async {
    setState(() {busy = true; error = null;});
    try {
      final child = isEdit
        ? await widget.onUpdate!(ChildProfileUpdate(displayName: name.text.trim(),
            schoolYear: year, avatarId: avatar, pin: newPin))
        : await widget.onSave!(ChildProfileDraft(requestId: requestId,
            displayName: name.text.trim(), schoolYear: year, avatarId: avatar, pin: newPin!));
      if (!mounted) return;
      firstPin = ''; pin = '';
      widget.onSaved(child);
    } on FamilyException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível guardar o perfil. Tenta novamente.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Widget keepPinCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(32),
      border: Border.all(color: AppColors.blueBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.lock_outline_rounded, color: Colors.white)),
        const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PIN Infantil', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text)),
          SizedBox(height: 4),
          Text('O PIN atual mantém-se. Ao alterá-lo, a criança terá de usar o novo código na próxima entrada.',
            style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
        ])),
      ]),
      if (error != null) ...[
        const SizedBox(height: 12),
        Text(error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 16),
      AppButton(label: 'Alterar PIN', icon: Icons.password_rounded, variant: AppButtonVariant.secondary,
        onPressed: busy ? null : () => setState(() {changePin = true; pin = ''; error = null; inputVersion++;})),
    ]),
  );

  Widget sectionLabel(IconData icon, String text, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Icon(icon, color: AppColors.primary, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text))),
      if (trailing != null) trailing,
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(child: SingleChildScrollView(
      key: ValueKey('profile-$confirming'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: Padding(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (isEdit) Row(children: [
            IconButton.filledTonal(onPressed: busy ? null : back, tooltip: 'Voltar', icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 12),
            Expanded(child: Text('Editar perfil', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(width: 12),
            const CircleAvatar(backgroundColor: AppColors.lavender, child: Icon(Icons.manage_accounts_rounded, color: AppColors.primary)),
          ]) else OnboardingHeader(title: 'Perfil do Educando', step: 3, section: 'Perfil', icon: Icons.face_rounded,
            onBack: busy || (!confirming && widget.onBack == null) ? null : back),
          const SizedBox(height: 24),
          Text(confirming ? (isEdit ? 'Confirma o novo PIN Infantil' : 'Confirma o PIN Infantil')
            : isEdit ? 'Alterar perfil de ${widget.initial!.displayName}' : 'Identificação & PIN Infantil',
            style: const TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 8),
          Text(confirming ? 'Repete os mesmos 4 dígitos antes de guardar o perfil.'
            : isEdit ? 'Atualiza a alcunha, o avatar, o ano escolar ou o PIN de entrada da criança.'
            : 'Configura o espaço personalizado da criança, com diversão e autonomia segura.',
            style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.muted)),
          const SizedBox(height: 20),
          if (!confirming) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.lavender)),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 20, backgroundColor: AppColors.successSoft,
                  child: Icon(Icons.verified_user_outlined, color: AppColors.success, size: 22)),
                SizedBox(width: 12),
                Expanded(child: Text.rich(TextSpan(style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.text), children: [
                  TextSpan(text: 'Privacidade em primeiro lugar: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: 'sem datas de nascimento nem dados sensíveis. Só uma alcunha, um avatar e o ano escolar, para carinho e personalização.'),
                ]))),
              ]),
            ),
            const SizedBox(height: 20),
            AppCard(child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              sectionLabel(Icons.badge_outlined, 'Como quer que a app lhe chame?',
                trailing: const Text('Obrigatório', style: TextStyle(fontSize: 13, color: AppColors.muted))),
              TextFormField(
                controller: name, enabled: !busy,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                textCapitalization: TextCapitalization.words,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                validator: (value) => value == null || value.trim().isEmpty ? 'Indica a alcunha da criança.' : null,
                decoration: InputDecoration(
                  hintText: 'Alcunha da criança',
                  filled: true, fillColor: AppColors.softBlue,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  suffixIcon: const Padding(padding: EdgeInsets.only(right: 8),
                    child: CircleAvatar(radius: 18, backgroundColor: AppColors.lavender,
                      child: Icon(Icons.edit_rounded, size: 18, color: AppColors.primary))),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                ),
              ),
              const SizedBox(height: 26),
              sectionLabel(Icons.sentiment_satisfied_alt_rounded, 'Escolhe o Avatar Amigo',
                trailing: Text('Escolhido: ${ChildAvatars.label(avatar)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary))),
              AvatarSelector(value: avatar, enabled: !busy, onChanged: (value) => setState(() => avatar = value)),
              const SizedBox(height: 26),
              sectionLabel(Icons.school_outlined, 'Ano Escolar (Ensino Básico)'),
              SchoolYearSelector(value: year, enabled: !busy, onChanged: (value) => setState(() => year = value)),
            ]))),
          ] else AppCard(child: Row(children: [
            Container(width: 64, height: 64, alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
              child: ExcludeSemantics(child: Text(ChildAvatars.emoji(avatar), style: const TextStyle(fontSize: 36)))),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.text.trim(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('$year.º Ano • ${ChildAvatars.label(avatar)}', style: const TextStyle(color: AppColors.muted)),
            ])),
            TextButton.icon(onPressed: busy ? null : back, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Editar')),
          ])),
          const SizedBox(height: 20),
          if (!needsPin) keepPinCard() else Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.blueBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.lock_outline_rounded, color: Colors.white)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(confirming ? 'Repetir PIN Infantil' : isEdit ? 'Novo PIN Infantil (4 Dígitos)' : 'PIN Infantil (4 Dígitos)',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.text))),
                    if (isEdit && !confirming) TextButton(onPressed: busy ? null : () => setState(() {
                      changePin = false; pin = ''; error = null; inputVersion++;
                    }), child: const Text('Manter atual')),
                  ]),
                  const SizedBox(height: 4),
                  const Text('Um código simples para a criança entrar sozinha no seu espaço de fichas e aventuras.',
                    style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
                ])),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Expanded(child: Text('CÓDIGO DE ACESSO',
                      style: TextStyle(fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: AppColors.muted))),
                    if (pin.length == 4) const Row(children: [
                      Icon(Icons.lock_rounded, size: 16, color: AppColors.success), SizedBox(width: 4),
                      Text('Pronto', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
                    ]),
                  ]),
                  const SizedBox(height: 14),
                  Center(child: AppPinInput(key: ValueKey(inputVersion),
                    label: confirming ? 'Repete o código' : 'Escolhe 4 números',
                    enabled: !busy, errorText: error,
                    onChanged: (value) => setState(() {pin = value; error = null;}))),
                ]),
              ),
              const SizedBox(height: 14),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted), SizedBox(width: 8),
                Expanded(child: Text('Usa um PIN diferente do PIN do responsável e fácil de lembrar para a criança.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted))),
              ]),
            ]),
          ),
          const SizedBox(height: 28),
          AppButton(label: confirming ? (isEdit ? 'Guardar alterações' : 'Guardar Perfil & Avançar')
              : needsPin ? 'Continuar e confirmar PIN' : 'Guardar alterações',
            icon: needsPin && !confirming ? Icons.arrow_forward_rounded : Icons.check_rounded,
            variant: confirming || !needsPin ? AppButtonVariant.success : AppButtonVariant.primary,
            loading: busy, onPressed: busy || (needsPin && pin.length != 4) ? null : submit),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success), const SizedBox(width: 6),
            Flexible(child: Text(isEdit ? 'As alterações aplicam-se de imediato ao espaço infantil.'
              : 'A alcunha, o avatar e o ano escolar ficam guardados na tua família.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
          ]),
          const SizedBox(height: 24),
        ]),
      ))),
    )),
  );
}
