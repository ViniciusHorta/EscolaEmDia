import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand/app_logo.dart';
import '../../../shared/widgets/layout/app_page.dart';
import '../data/auth_service.dart';
import 'family_account_page.dart';
import 'new_password_page.dart';
import '../../parent_pin/presentation/parent_pin_gate.dart';
import '../../family/presentation/family_workspace_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<AuthService> startup;
  AuthService? service;

  @override
  void initState() {
    super.initState();
    startup = initialize();
  }

  Future<AuthService> initialize() async {
    final supabase = await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.publishableKey,
      debug: false,
    );
    final auth = AuthService(supabase.client);
    if (!mounted) {
      auth.dispose();
    } else {
      service = auth;
    }
    return auth;
  }

  @override
  void dispose() {
    service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AuthService>(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AppPage(
          title: 'Vamos tentar outra vez?',
          subtitle: 'Não foi possível abrir a tua sessão.',
          children: [AppButton(label: 'Tentar novamente', onPressed: () {
            setState(() => startup = initialize());
          })],
        );
      }
      if (!snapshot.hasData) {
        return const AppSplash();
      }
      final auth = snapshot.data!;
      return ListenableBuilder(
        listenable: auth,
        builder: (context, _) => !auth.signedIn
            ? FamilyAccountPage(auth: auth)
            : auth.recoveringPassword
                ? NewPasswordPage(auth: auth)
                : auth.emailConfirmed
                    ? ParentPinGate(
                        key: ValueKey(auth.user!.id),
                        auth: auth,
                        child: FamilyWorkspacePage(key: ValueKey(auth.user!.id), auth: auth),
                      )
                    : AccountSessionPage(auth: auth),
      );
    },
  );
}

class AccountSessionPage extends StatefulWidget {
  const AccountSessionPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<AccountSessionPage> createState() => _AccountSessionPageState();
}

class _AccountSessionPageState extends State<AccountSessionPage> {
  bool busy = false;
  String? feedback;

  Future<void> perform(Future<void> Function() action, {String? success}) async {
    if (busy) return;
    setState(() { busy = true; feedback = null; });
    try {
      await action();
      if (mounted) setState(() => feedback = success);
    } catch (error) {
      if (mounted) setState(() => feedback = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final confirmed = auth.emailConfirmed;
    return AppPage(
      title: confirmed ? 'Bem-vindo à tua área familiar' : 'Confirma o teu e-mail',
      subtitle: confirmed
          ? 'A tua sessão está iniciada e o PIN do responsável está configurado.'
          : 'Abre o e-mail de confirmação para concluir a criação da conta.',
      children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(confirmed ? Icons.verified_user_outlined : Icons.mark_email_unread_outlined,
            size: 56, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(auth.user?.email ?? '', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
          if (!confirmed) ...[
            const SizedBox(height: 24),
            AppButton(label: 'Já confirmei o e-mail', loading: busy,
              onPressed: busy ? null : () => perform(auth.refreshConfirmation)),
            const SizedBox(height: 16),
            AppButton(label: 'Reenviar confirmação', variant: AppButtonVariant.secondary,
              onPressed: busy || auth.user?.email == null ? null : () => perform(
                () => auth.resendConfirmation(auth.user!.email!),
                success: 'Verifica a caixa de entrada e a pasta de spam.',
              )),
          ],
          if (feedback != null || auth.streamError != null) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(feedback ?? auth.streamError!)),
          ],
          const SizedBox(height: 24),
          AppButton(label: 'Sair da conta', variant: AppButtonVariant.secondary,
            loading: confirmed && busy,
            onPressed: busy ? null : () => perform(auth.signOut)),
        ])),
      ],
    );
  }
}
