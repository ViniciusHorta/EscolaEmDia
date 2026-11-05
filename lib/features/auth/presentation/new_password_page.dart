import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/auth_service.dart';
import 'widgets/auth_shell.dart';

/// Passo 2 da recuperação: aberto pelo AuthGate quando o link do e-mail chega
/// à app (evento passwordRecovery). Bloqueia o acesso até definir a palavra-passe.
class NewPasswordPage extends StatefulWidget {
  const NewPasswordPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends State<NewPasswordPage> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool showPassword = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !(form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.updatePassword(password.text);
      messenger.showSnackBar(const SnackBar(content: Text('Palavra-passe atualizada. Bem-vindo de volta!')));
    } catch (e) {
      if (mounted) setState(() => error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.auth.signOut();
    } catch (e) {
      if (mounted) setState(() => error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget visibilityToggle() => IconButton(
    tooltip: showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe',
    onPressed: busy ? null : () => setState(() => showPassword = !showPassword),
    icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
  );

  @override
  Widget build(BuildContext context) {
    final email = widget.auth.user?.email;
    return AuthShell(child: Form(
      key: form,
      child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AuthCardHeader(
          icon: Icons.lock_reset_rounded,
          title: 'Define uma nova palavra-passe',
          subtitle: email == null
              ? 'Escolhe uma palavra-passe nova para a conta familiar.'
              : 'Escolhe uma palavra-passe nova para $email.',
        ),
        const SizedBox(height: 28),
        AppTextField(
          label: 'Nova palavra-passe',
          hint: 'Mínimo de 8 caracteres',
          controller: password,
          enabled: !busy,
          obscureText: !showPassword,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          prefixIcon: Icons.key_rounded,
          suffixIcon: visibilityToggle(),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Indica a nova palavra-passe.';
            if (value.length < 8) return 'Usa pelo menos 8 caracteres.';
            return null;
          },
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Confirmar nova palavra-passe',
          hint: 'Repete a palavra-passe',
          controller: confirmation,
          enabled: !busy,
          obscureText: !showPassword,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          prefixIcon: Icons.key_rounded,
          onSubmitted: (_) => save(),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Repete a nova palavra-passe.';
            if (value != password.text) return 'As palavras-passe não coincidem.';
            return null;
          },
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          AuthFeedback(error!, error: true),
        ],
        const SizedBox(height: 24),
        AppButton(
          label: 'Guardar e entrar',
          icon: Icons.arrow_forward_rounded,
          loading: busy,
          onPressed: busy ? null : save,
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(
          onPressed: busy ? null : cancel,
          child: const Text('Cancelar e sair'),
        )),
      ])),
    ));
  }
}
