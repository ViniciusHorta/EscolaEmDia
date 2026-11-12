import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService(this.client) {
    _subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          recoveringPassword = true;
        } else if (state.event == AuthChangeEvent.signedOut) {
          recoveringPassword = false;
        }
        _verifiedUser = null;
        streamError = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        streamError = messageFor(error);
        notifyListeners();
      },
    );
  }

  final SupabaseClient client;
  late final StreamSubscription<AuthState> _subscription;
  String? streamError;

  /// Verdadeiro depois de abrir um link de recuperação: a sessão existe, mas a
  /// pessoa tem de definir uma nova palavra-passe antes de entrar na app.
  bool recoveringPassword = false;
  User? _verifiedUser;

  User? get user => _verifiedUser ?? client.auth.currentUser;
  bool get signedIn => client.auth.currentSession != null;
  bool get emailConfirmed => user?.emailConfirmedAt != null;

  /// Deep link da app nativa; registado no AndroidManifest e nas
  /// Redirect URLs do Supabase Auth.
  static const mobileRedirectUrl = 'escolaemdia://login-callback/';

  String get _redirectUrl => kIsWeb
      ? Uri.base.replace(query: '', fragment: '').toString()
      : mobileRedirectUrl;

  /// [legalDocumentIds]: versões dos documentos legais aceites no formulário. O servidor
  /// regista o aceite no momento da criação da conta (trigger em auth.users).
  Future<bool> register(String email, String password, {List<String> legalDocumentIds = const []}) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _redirectUrl,
      data: {if (legalDocumentIds.isNotEmpty) 'legal_acceptances': legalDocumentIds},
    );
    return response.session == null;
  }

  Future<void> login(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Abre o consentimento do Google (browser / Custom Tab). A sessão chega depois
  /// via [onAuthStateChange], quando o redirect volta à app; por isso este método
  /// termina assim que o ecrã de autenticação é aberto.
  ///
  /// Contas novas criadas por aqui não trazem `legal_acceptances`: o
  /// LegalConsentGate pede o aceite dos documentos no primeiro acesso.
  Future<void> signInWithGoogle() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _redirectUrl,
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
    if (!launched) throw const AuthException('Could not launch Google sign-in', code: 'oauth_launch_failed');
  }

  Future<void> resendConfirmation(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: _redirectUrl,
    );
  }

  Future<void> requestPasswordReset(String email) =>
      client.auth.resetPasswordForEmail(email.trim(), redirectTo: _redirectUrl);

  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
    recoveringPassword = false;
    notifyListeners();
  }

  Future<void> refreshConfirmation() async {
    final response = await client.auth.getUser();
    _verifiedUser = response.user;
    notifyListeners();
  }

  Future<void> signOut() async {
    await client.auth.signOut(scope: SignOutScope.local);
  }

  static String messageFor(Object error) {
    if (error is AuthException) {
      if (error.statusCode == '429') {
        return 'Demasiadas tentativas. Aguarda um pouco antes de tentar novamente.';
      }
      return switch (error.code) {
        'invalid_credentials' => 'O e-mail ou a palavra-passe não estão corretos.',
        'email_not_confirmed' => 'Confirma o teu e-mail antes de entrar.',
        'user_already_exists' => 'Não foi possível criar a conta. Experimenta entrar.',
        'weak_password' => 'Escolhe uma palavra-passe mais forte, com pelo menos 8 caracteres.',
        'email_address_invalid' => 'Indica um endereço de e-mail válido.',
        'email_address_not_authorized' => 'Não foi possível enviar o e-mail para este endereço. Contacta o responsável pela aplicação.',
        'same_password' => 'A nova palavra-passe tem de ser diferente da anterior.',
        'otp_expired' => 'O link de recuperação expirou ou já foi usado. Pede um novo link.',
        'flow_state_not_found' || 'flow_state_expired' || 'bad_code_verifier' =>
          'Abre o link de recuperação no mesmo dispositivo e navegador onde o pediste, ou pede um novo link.',
        'oauth_launch_failed' => 'Não foi possível abrir o Google. Verifica se tens um navegador disponível e tenta novamente.',
        'provider_disabled' => 'A entrada com o Google está temporariamente indisponível.',
        'identity_already_exists' => 'Esta conta Google já está associada a outro utilizador.',
        'signup_disabled' =>'A criação de novas contas está temporariamente indisponível.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Aguarda alguns minutos antes de pedir um novo e-mail ou tentar novamente.',
        _ => 'Não foi possível concluir o pedido. Tenta novamente dentro de alguns instantes.',
      };
    }
    return 'Não foi possível ligar ao serviço. Verifica a ligação à Internet e tenta novamente.';
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
