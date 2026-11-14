import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/layout/onboarding_header.dart';
import '../../../shared/widgets/pin/app_pin_input.dart';
import '../../auth/presentation/widgets/email_code_field.dart';
import '../data/parent_access_service.dart';
import '../data/parent_pin_service.dart';

/// Recuperação do PIN do responsável: confirmar a identidade (palavra-passe ou código
/// enviado por e-mail, obrigatório para contas criadas com o Google) e definir um PIN novo. Devolve `true` se a área do responsável ficou desbloqueada com o novo PIN.
class ParentPinResetPage extends StatefulWidget {
  const ParentPinResetPage({super.key, required this.service, required this.access});
  final ParentPinService service;
  final ParentAccessService access;

  @override
  State<ParentPinResetPage> createState() => _ParentPinResetPageState();
}

enum _Step { identity, newPin, confirmPin }

class _ParentPinResetPageState extends State<ParentPinResetPage> {
  final password = TextEditingController();
  final code = TextEditingController();
  _Step step = _Step.identity;
  /// Confirmar com código por e-mail em vez da palavra-passe.
  late bool useCode = !widget.service.hasPassword;
  /// Muda a chave do [EmailCodeField] para recomeçar o envio ao voltar a este passo.
  int codeVersion = 0;
  bool showPassword = false;
  bool busy = false;
  String firstPin = '';
  String pin = '';
  int inputVersion = 0;
  String? error;

  String? get email => widget.service.client.auth.currentUser?.email;

  @override
  void dispose() {
    password.dispose();
    code.dispose();
    firstPin = '';
    pin = '';
    super.dispose();
  }

  void back() {
    if (busy) return;
    switch (step) {
      case _Step.identity:
        Navigator.of(context).pop(false);
      case _Step.newPin:
        setState(() { step = _Step.identity; pin = ''; error = null; });
      case _Step.confirmPin:
        setState(() { step = _Step.newPin; firstPin = ''; pin = ''; error = null; inputVersion++; });
    }
  }

  Future<void> confirmPassword() async {
    if (busy) return;
    if (password.text.isEmpty) {
      setState(() => error = 'Indica a palavra-passe da conta.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; });
    try {
      await widget.service.reauthenticate(password.text);
      if (!mounted) return;
      password.clear();
      setState(() { step = _Step.newPin; pin = ''; inputVersion++; });
    } on ParentPinException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmCode() async {
    if (busy) return;
    if (code.text.trim().isEmpty) {
      setState(() => error = 'Indica o código que recebeste por e-mail.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; });
    try {
      await widget.service.reauthenticateWithCode(code.text);
      if (!mounted) return;
      code.clear();
      setState(() { step = _Step.newPin; pin = ''; inputVersion++; });
    } on ParentPinException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void switchMethod(bool toCode) {
    if (busy) return;
    password.clear();
    code.clear();
    setState(() { useCode = toCode; error = null; codeVersion++; });
  }

  Future<void> continuePin() async {
    if (busy || pin.length != 4) return;
    if (step == _Step.newPin) {
      setState(() { firstPin = pin; pin = ''; step = _Step.confirmPin; error = null; inputVersion++; });
      return;
    }
    if (pin != firstPin) {
      setState(() { error = 'Os PINs não coincidem. Repete o novo PIN.'; pin = ''; inputVersion++; });
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.service.reset(pin);
    } on ParentPinException catch (failure) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = failure.message;
        if (failure.reauthRequired) {
          // Passaram mais de cinco minutos desde a confirmação da identidade.
          step = _Step.identity; firstPin = ''; pin = ''; codeVersion++;
        } else {
          pin = ''; inputVersion++;
        }
      });
      return;
    }
    // O PIN já foi alterado; desbloquear é uma conveniência. Se falhar, o ecrã
    // de desbloqueio pede o novo PIN.
    var unlocked = false;
    try {
      await widget.access.verify(pin);
      unlocked = widget.access.unlocked;
    } catch (_) {}
    firstPin = ''; pin = '';
    if (mounted) Navigator.of(context).pop(unlocked);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && step == _Step.identity,
    onPopInvokedWithResult: (didPop, _) { if (!didPop) back(); },
    child: Scaffold(body: SafeArea(child: SingleChildScrollView(
      key: ValueKey(step),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OnboardingHeader(
              title: 'Recuperar PIN do responsável',
              step: step == _Step.identity ? 1 : 2,
              total: 2,
              section: step == _Step.identity ? 'Confirmar identidade' : 'Novo PIN',
              icon: Icons.lock_reset_rounded,
              onBack: busy ? null : back,
            ),
            const SizedBox(height: 32),
            if (step == _Step.identity) identityStep() else pinStep(),
          ]),
        ),
      )),
    ))),
  );

  Widget identityStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Confirma que és tu', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 12),
    Text(useCode
        ? 'Para proteger a área do responsável, confirma o código enviado para o e-mail da conta.'
        : 'Para proteger a área do responsável, introduz a palavra-passe da conta${email == null ? '' : ' $email'}.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
    const SizedBox(height: 28),
    AppCard(child: useCode ? codeForm() : passwordForm()),
    if (widget.service.hasPassword) ...[
      const SizedBox(height: 12),
      Center(child: TextButton(
        onPressed: busy ? null : () => switchMethod(!useCode),
        child: Text(useCode ? 'Usar a palavra-passe' : 'Esqueci-me da palavra-passe: receber um código por e-mail',
          textAlign: TextAlign.center),
      )),
    ],
  ]);

  Widget passwordForm() => AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    AppTextField(
      label: 'Palavra-passe da conta',
      hint: 'A tua palavra-passe',
      controller: password,
      enabled: !busy,
      obscureText: !showPassword,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      prefixIcon: Icons.key_rounded,
      errorText: error,
      onChanged: (_) { if (error != null) setState(() => error = null); },
      onSubmitted: (_) => confirmPassword(),
      suffixIcon: IconButton(
        tooltip: showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe',
        onPressed: busy ? null : () => setState(() => showPassword = !showPassword),
        icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      ),
    ),
    const SizedBox(height: 24),
    AppButton(label: 'Confirmar palavra-passe', icon: Icons.arrow_forward_rounded,
      loading: busy, onPressed: busy ? null : confirmPassword),
  ]));

  Widget codeForm() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    EmailCodeField(
      key: ValueKey(codeVersion),
      controller: code,
      email: email,
      enabled: !busy,
      errorText: error,
      onSend: () async {
        try {
          await widget.service.sendReauthCode();
          return null;
        } on ParentPinException catch (failure) {
          return failure.message;
        }
      },
      onChanged: (_) => setState(() => error = null),
      onSubmitted: (_) => confirmCode(),
    ),
    if (code.text.isNotEmpty || error != null) ...[
      const SizedBox(height: 16),
      AppButton(label: 'Confirmar código', icon: Icons.arrow_forward_rounded,
        loading: busy, onPressed: busy || code.text.trim().isEmpty ? null : confirmCode),
    ],
  ]);

  Widget pinStep() {
    final confirming = step == _Step.confirmPin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(confirming ? 'Confirma o novo PIN' : 'Define um novo PIN do responsável',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Text(confirming
          ? 'Repete os mesmos 4 dígitos.'
          : 'Escolhe 4 dígitos diferentes do PIN das crianças.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
      const SizedBox(height: 28),
      Center(child: AppPinInput(
        key: ValueKey(inputVersion),
        label: confirming ? 'Repetir novo PIN' : 'Novo PIN do responsável',
        enabled: !busy,
        errorText: error,
        onChanged: (value) => setState(() { pin = value; error = null; }),
      )),
      const SizedBox(height: 32),
      AppButton(
        label: confirming ? 'Guardar novo PIN' : 'Continuar',
        icon: confirming ? Icons.check_rounded : Icons.arrow_forward_rounded,
        loading: busy,
        onPressed: busy || pin.length != 4 ? null : continuePin,
      ),
      const SizedBox(height: 18),
      const Text('Ao guardar, todos os dispositivos com a área do responsável aberta voltam a pedir o PIN.',
        textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
    ]);
  }
}
