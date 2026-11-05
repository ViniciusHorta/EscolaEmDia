import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService(this.client) {
    _subscription = client.auth.onAuthStateChange.listen(
      (_) {
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
  User? _verifiedUser;

  User? get user => _verifiedUser ?? client.auth.currentUser;
  bool get signedIn => client.auth.currentSession != null;
  bool get emailConfirmed => user?.emailConfirmedAt != null;

  String? get _redirectUrl => kIsWeb
      ? Uri.base.replace(query: '', fragment: '').toString()
      : null;

  Future<bool> register(String email, String password) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _redirectUrl,
    );
    return response.session == null;
  }

  Future<void> login(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> resendConfirmation(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: _redirectUrl,
    );
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
        'signup_disabled' => 'A criação de novas contas está temporariamente indisponível.',
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
