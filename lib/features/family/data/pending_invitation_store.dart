import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Convite recebido por e-mail (`/convite?token=inv_…`) à espera de ser aceite.
/// Fica guardado no dispositivo para sobreviver ao login, à criação de conta e à
/// confirmação do e-mail (cujo redirecionamento perde a query string).
abstract final class PendingInvitationStore {
  static const _key = 'pending-family-invitation';
  static final _format = RegExp(r'^inv_[0-9a-f]{64}$');

  static bool isValid(String? token) => token != null && _format.hasMatch(token);

  /// Lê o token do endereço atual (só na Web) e guarda-o. Chamado no arranque.
  static Future<void> captureFromUrl([Uri? url]) async {
    if (!kIsWeb && url == null) return;
    final token = (url ?? Uri.base).queryParameters['token'];
    if (isValid(token)) await save(token!);
  }

  static Future<void> save(String token) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, token);
    } catch (_) {/* sem armazenamento: o convite só vale nesta visita */}
  }

  static Future<String?> read() async {
    try {
      final token = (await SharedPreferences.getInstance()).getString(_key);
      return isValid(token) ? token : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {/* ignora */}
  }
}
