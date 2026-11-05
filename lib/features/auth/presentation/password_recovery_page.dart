import 'dart:async';
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/auth_service.dart';
import 'widgets/auth_shell.dart';

/// Passo 1 da recuperação: pedir o link por e-mail.
class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key, required this.auth, this.initialEmail = ''});
  final AuthService auth;
  final String initialEmail;

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  static const resendDelay = 60;

  final form = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.initialEmail.trim());
  bool busy = false;
  String? sentTo;
  String? error;
  int cooldown = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(closeWhenSignedIn);
  }

  /// Se o link for aberto enquanto este ecrã está aberto, a sessão de
  /// recuperação chega ao AuthGate; fecha-se para mostrar a nova palavra-passe.
  void closeWhenSignedIn() {
    if (mounted && widget.auth.signedIn) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(closeWhenSignedIn);
    timer?.cancel();
    email.dispose();
    super.dispose();
  }

  void startCooldown() {
    timer?.cancel();
    setState(() => cooldown = resendDelay);
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => cooldown--);
      if (cooldown <= 0) t.cancel();
    });
  }

  Future<void> send({bool resend = false}) async {
    if (busy || cooldown > 0) return;
    if (!resend && !(form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final address = resend ? sentTo! : email.text.trim();
    setState(() { busy = true; error = null; });
    try {
      await widget.auth.requestPasswordReset(address);
      if (!mounted) return;
      setState(() => sentTo = address);
      startCooldown();
    } catch (e) {
      if (mounted) setState(() => error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void back() => Navigator.of(context).pop(sentTo ?? email.text.trim());

  @override
  Widget build(BuildContext context) => AuthShell(
    child: sentTo == null ? requestForm() : sentConfirmation(),
  );

  Widget requestForm() => Form(
    key: form,
    child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AuthCardHeader(
        icon: Icons.key_rounded,
        title: 'Recuperar o acesso',
        subtitle: 'Indica o e-mail da conta familiar. Vamos enviar-te um link para definires uma nova palavra-passe.',
        onBack: busy ? null : back,
      ),
      const SizedBox(height: 28),
      AppTextField(
        label: 'E-mail do encarregado de educação',
        hint: 'exemplo@email.pt',
        controller: email,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.send,
        autofillHints: const [AutofillHints.email],
        prefixIcon: Icons.mail_outline_rounded,
        onSubmitted: (_) => send(),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Indica o teu e-mail.';
          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
            return 'Indica um endereço de e-mail válido.';
          }
          return null;
        },
      ),
      if (error != null) ...[
        const SizedBox(height: 20),
        AuthFeedback(error!, error: true),
      ],
      const SizedBox(height: 24),
      AppButton(
        label: 'Enviar link de recuperação',
        icon: Icons.send_rounded,
        loading: busy,
        onPressed: busy ? null : send,
      ),
      const SizedBox(height: 12),
      Center(child: TextButton(
        onPressed: busy ? null : back,
        child: const Text('Afinal lembro-me, voltar para entrar'),
      )),
    ])),
  );

  Widget sentConfirmation() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    AuthCardHeader(
      icon: Icons.mark_email_read_outlined,
      title: 'Verifica o teu e-mail',
      // Mensagem neutra: não revela se existe conta associada ao endereço.
      subtitle: 'Se existir uma conta associada a $sentTo, vais receber um link para definir uma nova palavra-passe.',
    ),
    const SizedBox(height: 24),
    const AuthFeedback('Abre o link neste dispositivo. Se não o encontrares, procura também na pasta de spam.'),
    if (error != null) ...[
      const SizedBox(height: 16),
      AuthFeedback(error!, error: true),
    ],
    const SizedBox(height: 24),
    AppButton(
      label: 'Voltar para entrar',
      icon: Icons.login_rounded,
      onPressed: busy ? null : back,
    ),
    const SizedBox(height: 12),
    AppButton(
      label: cooldown > 0 ? 'Reenviar link (${cooldown}s)' : 'Reenviar link',
      variant: AppButtonVariant.secondary,
      loading: busy,
      onPressed: busy || cooldown > 0 ? null : () => send(resend: true),
    ),
    Center(child: TextButton(
      onPressed: busy ? null : () => setState(() { sentTo = null; error = null; }),
      child: const Text('Usar outro e-mail'),
    )),
  ]);
}
