import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../family/domain/family_models.dart';
import '../../worksheets/domain/worksheet_models.dart';

class ChildSessionException implements Exception {
  const ChildSessionException(this.message, {this.ended = false, this.retryAfter});
  final String message;
  final bool ended;
  final int? retryAfter;
}

abstract final class ChildModeStore {
  // A navigation preference only. Never persist the PIN or child bearer token.
  static String key(String adultId) => 'child-mode-family-$adultId';
  static Future<String?> read(String adultId) async =>
      (await SharedPreferences.getInstance()).getString(key(adultId));
  static Future<void> enter(String adultId, String familyId) async {
    if (!await (await SharedPreferences.getInstance()).setString(key(adultId), familyId)) {
      throw const ChildSessionException('Não foi possível abrir o espaço infantil neste dispositivo.');
    }
  }
  static Future<void> clear(String adultId) async {
    await (await SharedPreferences.getInstance()).remove(key(adultId));
  }
}

class ChildSessionService {
  ChildSessionService(this.adultClient);
  final SupabaseClient adultClient;
  final http.Client _http = http.Client();
  String? _token;
  DateTime? expiresAt;

  Future<ChildProfile> login(String childId, String pin) async {
    if (_token != null) await endSession();
    try {
      var session = adultClient.auth.currentSession;
      if (session?.isExpired == true) session = (await adultClient.auth.refreshSession()).session;
      if (session == null) throw const ChildSessionException('É necessário entrar com a conta do adulto.');
      final response = await adultClient.functions.invoke('child-sessions/v1/child-sessions',
        body: {'childId': childId, 'pin': pin},
        headers: {'Authorization': 'Bearer ${session.accessToken}'});
      final data = response.data;
      if (data is! Map || data['accessToken'] is! String || data['expiresAt'] is! String) {
        throw const ChildSessionException('Não foi possível confirmar a entrada. Tenta novamente.');
      }
      _token = data['accessToken'] as String;
      expiresAt = DateTime.parse(data['expiresAt'] as String);
      // Resolve the profile from the child token, never from the selected card.
      return await profile();
    } on ChildSessionException { rethrow; }
    on FunctionException catch (error) { throw _error(error.details); }
    catch (_) { throw const ChildSessionException('Não foi possível entrar. Verifica a ligação e tenta novamente.'); }
  }

  Future<ChildProfile> profile() async {
    final data = await _childRequest('/me', 'GET');
    if (data['child'] is! Map) throw const ChildSessionException('Não foi possível carregar o teu perfil.');
    final validUntil = data['expiresAt'] is String ? DateTime.tryParse(data['expiresAt'] as String) : null;
    if (validUntil == null || !validUntil.isAfter(DateTime.now())) {
      _forget();
      throw const ChildSessionException('A tua sessão terminou. Entra novamente com o PIN.', ended: true);
    }
    expiresAt = validUntil;
    return ChildProfile.fromJson(data['child'] as Map);
  }

  Future<void> endSession() async {
    if (_token == null) return;
    try { await _childRequest('/revoke', 'POST'); }
    on ChildSessionException catch (error) { if (!error.ended) rethrow; }
    _forget();
  }

  void forgetExpired() {
    if (expiresAt != null && !expiresAt!.isAfter(DateTime.now())) _forget();
  }

  Future<List<AssignedWorksheet>> assignments(String childId) async {
    final result=<AssignedWorksheet>[]; String? cursor; final seen=<String>{};
    do {
      final uri=Uri.parse('${SupabaseConfig.url}/functions/v1/worksheets/v1/children/$childId/assignments')
        .replace(queryParameters:cursor==null?null:{'cursor':cursor});
      final page=await _sendChildRequest(uri,'GET');
      final items=page['items'];
      if(items is! List || items.any((item)=>item is! Map))throw const ChildSessionException('Não foi possível carregar as fichas.');
      result.addAll(items.cast<Map>().map(AssignedWorksheet.fromJson));
      final next=page['nextCursor'];
      if(next!=null && (next is! String || !seen.add(next)))throw const ChildSessionException('Não foi possível concluir a consulta das fichas.');
      cursor=next as String?;
    }while(cursor!=null);
    return result;
  }

  Future<Map> _childRequest(String suffix,String method) => _sendChildRequest(
    Uri.parse('${SupabaseConfig.url}/functions/v1/child-sessions/v1/child-sessions$suffix'),method);

  Future<Map> _sendChildRequest(Uri uri, String method) async {
    final token = _token;
    if (token == null) throw const ChildSessionException('Escolhe o teu perfil e entra novamente.', ended: true);
    final request = http.Request(method, uri)..headers.addAll({
      'apikey': SupabaseConfig.publishableKey, 'Authorization': 'Bearer $token',
    });
    // Separate HTTP client: no Supabase adult-session credentials or fallback.
    try {
      final response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20))).timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        final error = _error(data);
        if (error.ended) _forget();
        throw error;
      }
      if (data is! Map) throw const ChildSessionException('Não foi possível confirmar o pedido.');
      return data;
    } on ChildSessionException { rethrow; }
    catch (_) { throw const ChildSessionException('Não foi possível ligar ao serviço. Tenta novamente.'); }
  }

  ChildSessionException _error(dynamic data) {
    final error = data is Map ? data['error'] : null;
    final message = error is Map ? error['message'] : null;
    final details = error is Map ? error['details'] : null;
    final wait = details is Map ? details['retryAfter'] : null;
    return ChildSessionException(message is String ? message : 'Não foi possível concluir o pedido. Tenta novamente.',
      ended: error is Map && error['code'] == 'CHILD_SESSION_EXPIRED',
      retryAfter: wait is num && wait > 0 ? wait.ceil() : null);
  }

  void _forget() { _token = null; expiresAt = null; }
  void dispose() { _forget(); _http.close(); }
}
