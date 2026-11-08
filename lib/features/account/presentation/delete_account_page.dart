import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/layout/onboarding_header.dart';
import '../data/account_service.dart';

/// Eliminar a conta do responsável: explica o que é apagado e o que fica, pede a
/// palavra-passe e a palavra ELIMINAR. Devolve `true` quando a conta foi eliminada
/// (a sessão local já terminou).
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key, required this.service});
  final AccountService service;

  static Future<bool> open(BuildContext context, AccountService service) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => DeleteAccountPage(service: service)),
      ) ==
      true;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool confirming = false;
  bool showPassword = false;
  bool busy = false;
  String? passwordError;
  String? error;

  String? get email => widget.service.client.auth.currentUser?.email;
  bool get confirmed => confirmation.text.trim().toUpperCase() == AccountService.confirmationWord;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void back() {
    if (busy) return;
    if (confirming) {
      setState(() { confirming = false; error = null; passwordError = null; });
    } else {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> delete() async {
    if (busy) return;
    if (password.text.isEmpty) {
      setState(() => passwordError = 'Indica a palavra-passe da conta.');
      return;
    }
    if (!confirmed) {
      setState(() => error = 'Escreve ${AccountService.confirmationWord} para confirmar.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { busy = true; error = null; passwordError = null; });
    try {
      await widget.service.reauthenticate(password.text);
    } on AccountException catch (failure) {
      if (mounted) setState(() { busy = false; passwordError = failure.message; });
      return;
    }
    password.clear();
    try {
      await widget.service.deleteAccount();
    } on AccountException catch (failure) {
      if (mounted) setState(() { busy = false; error = failure.message; });
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(const SnackBar(content: Text('A tua conta e os dados da família foram eliminados.')));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !confirming,
    onPopInvokedWithResult: (didPop, _) { if (!didPop) back(); },
    child: Scaffold(body: SafeArea(child: SingleChildScrollView(
      key: ValueKey(confirming),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 16 : 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OnboardingHeader(
              title: 'Eliminar conta',
              step: confirming ? 2 : 1,
              total: 2,
              section: confirming ? 'Confirmar' : 'O que acontece',
              icon: Icons.delete_forever_rounded,
              onBack: busy ? null : back,
            ),
            const SizedBox(height: 32),
            if (confirming) confirmStep() else infoStep(),
          ]),
        ),
      )),
    ))),
  );

  Widget bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(top: 7, right: 10),
        child: Icon(Icons.circle, size: 7, color: AppColors.muted)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.text))),
    ]),
  );

  Widget section(String title, List<String> items) => AppCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
      const SizedBox(height: 14),
      for (final item in items) bullet(item),
    ],
  ));

  Widget infoStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Eliminar a conta e os dados', textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 12),
    Text('A eliminação é imediata e definitiva. Não é possível recuperar a conta nem o histórico.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
    const SizedBox(height: 28),
    section('O que é apagado', const [
      'A tua conta: e-mail, palavra-passe, PIN do responsável e registo de aceite dos documentos legais.',
      'Os perfis das crianças, os PINs, as fichas atribuídas, as respostas, as revisões e o progresso.',
      'Os problemas que reportaste em perguntas.',
    ]),
    const SizedBox(height: 16),
    section('Bom saber', const [
      'Se outro adulto também gere a família, a família e as crianças ficam com ele. Só a tua conta sai.',
      'As fichas do catálogo não são dados teus e continuam disponíveis para outras famílias.',
      'As cópias de segurança são substituídas automaticamente e deixam de conter os teus dados no prazo máximo de 30 dias.',
    ]),
    const SizedBox(height: 28),
    AppButton(label: 'Continuar', icon: Icons.arrow_forward_rounded, variant: AppButtonVariant.danger,
      onPressed: () => setState(() => confirming = true)),
    const SizedBox(height: 8),
    AppButton(label: 'Manter a conta', variant: AppButtonVariant.secondary,
      onPressed: () => Navigator.of(context).pop(false)),
  ]);

  Widget confirmStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Confirma que és tu', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 12),
    Text('Introduz a palavra-passe da conta${email == null ? '' : ' $email'} e escreve ${AccountService.confirmationWord}.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
    const SizedBox(height: 28),
    AppCard(child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
        label: 'Palavra-passe da conta',
        hint: 'A tua palavra-passe',
        controller: password,
        enabled: !busy,
        obscureText: !showPassword,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.password],
        prefixIcon: Icons.key_rounded,
        errorText: passwordError,
        onChanged: (_) { if (passwordError != null) setState(() => passwordError = null); },
        suffixIcon: IconButton(
          tooltip: showPassword ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe',
          onPressed: busy ? null : () => setState(() => showPassword = !showPassword),
          icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        ),
      ),
      const SizedBox(height: 20),
      AppTextField(
        label: 'Escreve ${AccountService.confirmationWord}',
        hint: AccountService.confirmationWord,
        controller: confirmation,
        enabled: !busy,
        textInputAction: TextInputAction.done,
        prefixIcon: Icons.warning_amber_rounded,
        onChanged: (_) => setState(() => error = null),
        onSubmitted: (_) => delete(),
      ),
      if (error != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(AppRadii.input)),
          child: Text(error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
        ),
      ],
      const SizedBox(height: 24),
      AppButton(label: 'Eliminar conta definitivamente', icon: Icons.delete_forever_rounded,
        variant: AppButtonVariant.danger, loading: busy,
        onPressed: busy || !confirmed ? null : delete),
    ]))),
    const SizedBox(height: 20),
    const Text('Esqueceste-te da palavra-passe? Sai da conta e usa «Esqueceu-se do acesso?» no ecrã de entrada.',
      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
  ]);
}
