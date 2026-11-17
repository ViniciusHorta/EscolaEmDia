import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

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

  /// Login nativo (Android e iOS) só existe fora do web.
  static bool get nativeGoogle =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// "Iniciar sessão com a Apple" só é oferecido no iOS (exigência da App Store quando há login Google).
  static bool get appleAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void>? _googleInit;

  /// Entra com Google. Devolve false se a pessoa cancelou.
  ///
  /// Android/iOS: seletor de contas nativo; o ID token é trocado por uma sessão Supabase
  /// (signInWithIdToken). Web: consentimento no browser; a sessão chega depois via
  /// [onAuthStateChange].
  ///
  /// Contas novas criadas por aqui não trazem `legal_acceptances`: o
  /// LegalConsentGate pede o aceite dos documentos no primeiro acesso.
  Future<bool> signInWithGoogle() async {
    if (!nativeGoogle) {
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      if (!launched) throw const AuthException('Could not launch Google sign-in', code: 'oauth_launch_failed');
      return true;
    }
    final google = GoogleSignIn.instance;
    await (_googleInit ??= google.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS ? GoogleSignInConfig.iosClientId : null,
      serverClientId: GoogleSignInConfig.webClientId,
    ));
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate(scopeHint: const ['email', 'profile']);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return false;
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthException('Missing Google ID token', code: 'native_sign_in_failed');
    await client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    return true;
  }

  /// Entra com a Apple (iOS, folha nativa). Devolve false se a pessoa cancelou.
  Future<bool> signInWithApple() async {
    final rawNonce = _randomNonce();
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }
    final idToken = credential.identityToken;
    if (idToken == null) throw const AuthException('Missing Apple ID token', code: 'native_sign_in_failed');
    await client.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken, nonce: rawNonce);
    return true;
  }

  static String _randomNonce([int length = 32]) {
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
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
        'provider_disabled' => 'Esta forma de entrar está temporariamente indisponível.',
        'identity_already_exists' => 'Esta conta já está associada a outro utilizador.',
        'native_sign_in_failed' => 'Não foi possível concluir a entrada. Tenta novamente.',
        'signup_disabled' =>'A criação de novas contas está temporariamente indisponível.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Aguarda alguns minutos antes de pedir um novo e-mail ou tentar novamente.',
        _ => 'Não foi possível concluir o pedido. Tenta novamente dentro de alguns instantes.',
      };
    }
    if (error is GoogleSignInException || error is SignInWithAppleException) {
      return 'Não foi possível concluir a entrada. Tenta novamente.';
    }
    return 'Não foi possível ligar ao serviço. Verifica a ligação à Internet e tenta novamente.';
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
