import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/auth_service.dart';
import 'password_recovery_page.dart';
import 'widgets/account_mode_selector.dart';
import 'widgets/family_brand_card.dart';

class FamilyAccountPage extends StatefulWidget {
  const FamilyAccountPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<FamilyAccountPage> createState() => _FamilyAccountPageState();
}

class _FamilyAccountPageState extends State<FamilyAccountPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  AccountMode mode = AccountMode.register;
  bool showPassword = false;
  bool acceptedTerms = false;
  bool showTermsError = false;
  bool busy = false;
  String? feedback;
  String? confirmationEmail;

  bool get registering => mode == AccountMode.register;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void changeMode(AccountMode value) {
    if (busy || value == mode) return;
    FocusScope.of(context).unfocus();
    form.currentState?.reset();
    password.clear();
    setState(() {
      mode = value;
      feedback = null;
      confirmationEmail = null;
      showPassword = false;
      acceptedTerms = false;
      showTermsError = false;
    });
  }

  Future<void> submit() async {
    if (busy) return;
    final valid = form.currentState?.validate() ?? false;
    setState(() => showTermsError = registering && !acceptedTerms);
    if (!valid || showTermsError) return;
    FocusScope.of(context).unfocus();
    final isRegistration = registering;
    final submittedEmail = email.text.trim();
    setState(() { busy = true; feedback = null; confirmationEmail = null; });
    try {
      if (isRegistration) {
        final pending = await widget.auth.register(submittedEmail, password.text);
        if (!mounted) return;
        if (pending) {
          form.currentState?.reset();
          email.text = submittedEmail;
          password.clear();
          setState(() {
            mode = AccountMode.login;
            confirmationEmail = submittedEmail;
            feedback = 'Verifica a caixa de entrada e a pasta de spam para confirmar o e-mail. Se já tens conta, entra com os teus dados.';
          });
        }
      } else {
        await widget.auth.login(submittedEmail, password.text);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => feedback = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendConfirmation() async {
    if (busy || confirmationEmail == null) return;
    setState(() { busy = true; feedback = null; });
    try {
      await widget.auth.resendConfirmation(confirmationEmail!);
      if (mounted) setState(() => feedback = 'Verifica a caixa de entrada e a pasta de spam.');
    } catch (error) {
      if (mounted) setState(() => feedback = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openRecovery() async {
    FocusScope.of(context).unfocus();
    setState(() => feedback = null);
    final used = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PasswordRecoveryPage(auth: widget.auth, initialEmail: email.text),
    ));
    if (mounted && used != null && used.isNotEmpty) email.text = used;
  }

  void showDocument(String title) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text('Este documento será disponibilizado antes da abertura do registo.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const FamilyBrandCard(),
            const SizedBox(height: 24),
            AppCard(
              child: Form(
                key: form,
                child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AccountModeSelector(value: mode, onChanged: changeMode, enabled: !busy),
                  const SizedBox(height: 28),
                  AppTextField(
                    label: 'E-mail do encarregado de educação',
                    hint: 'exemplo@email.pt',
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    prefixIcon: Icons.mail_outline_rounded,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Indica o teu e-mail.';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
                        return 'Indica um endereço de e-mail válido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    label: registering ? 'Palavra-passe segura' : 'Palavra-passe',
                    hint: registering ? 'Mínimo de 8 caracteres' : 'A tua palavra-passe',
                    controller: password,
                    enabled: !busy,
                    obscureText: !showPassword,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    autofillHints: [registering ? AutofillHints.newPassword : AutofillHints.password],
                    prefixIcon: Icons.key_rounded,
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe',
                      onPressed: busy ? null : () => setState(() => showPassword = !showPassword),
                      icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Indica a palavra-passe.';
                      if (registering && value.length < 8) return 'Usa pelo menos 8 caracteres.';
                      return null;
                    },
                  ),
                  if (registering) ...[
                    const SizedBox(height: 20),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(
                        value: acceptedTerms,
                        isError: showTermsError,
                        semanticLabel: 'Aceitar os Termos de Utilização e a Política de Privacidade',
                        onChanged: busy ? null : (value) => setState(() {
                          acceptedTerms = value ?? false;
                          showTermsError = false;
                        }),
                      ),
                      Expanded(child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          const Text('Li e aceito os '),
                          documentLink('Termos de Utilização'),
                          const Text(' e a '),
                          documentLink('Política de Privacidade'),
                          const Text('.'),
                        ]),
                      )),
                    ]),
                    if (showTermsError) Semantics(
                      liveRegion: true,
                      child: const Text('Aceita os termos para continuar.', style: TextStyle(color: AppColors.error)),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight,
                      child: TextButton(onPressed: busy ? null : openRecovery, child: const Text('Esqueceu-se do acesso?'))),
                  ],
                  if (feedback != null || widget.auth.streamError != null) ...[
                    const SizedBox(height: 20),
                    Semantics(liveRegion: true, child: AppCard(
                      color: AppColors.softBlue,
                      padding: const EdgeInsets.all(16),
                      child: Text(feedback ?? widget.auth.streamError!),
                    )),
                  ],
                  if (confirmationEmail != null) TextButton(
                    onPressed: busy ? null : resendConfirmation,
                    child: const Text('Reenviar e-mail de confirmação'),
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: registering ? 'Continuar para Configuração Familiar' : 'Entrar na minha conta',
                    icon: Icons.arrow_forward_rounded,
                    loading: busy,
                    onPressed: busy ? null : submit,
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    const Expanded(child: Divider()),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou acesso imediato')),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 24),
                  const Row(children: [
                    Expanded(child: AppButton(label: 'Apple', icon: Icons.apple, variant: AppButtonVariant.secondary, onPressed: null)),
                    SizedBox(width: 12),
                    Expanded(child: AppButton(label: 'Google', variant: AppButtonVariant.secondary, onPressed: null)),
                  ]),
                ])),
              ),
            ),
            const SizedBox(height: 24),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.muted, size: 20),
              SizedBox(width: 10),
              Flexible(child: Text('Apoio escolar pensado para as famílias em Portugal',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13))),
            ]),
            if (kDebugMode) ...[
              const SizedBox(height: 20),
              Center(child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/components'),
                icon: const Icon(Icons.widgets_outlined),
                label: const Text('Ver componentes'),
              )),
            ],
            const SizedBox(height: 24),
          ]),
        ),
      )),
    )),
  );

  Widget documentLink(String title) => TextButton(
    onPressed: () => showDocument(title),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      minimumSize: const Size(0, 48),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(title),
  );
}
