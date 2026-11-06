import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ParentAccessException implements Exception {
  const ParentAccessException(this.message, {this.retryAfter});
  final String message;
  final int? retryAfter;
}

class ParentAccessService extends ChangeNotifier {
  ParentAccessService(this.client);
  final SupabaseClient client;
  String? _token;
  DateTime? _expiresAt;
  DateTime? _lastActivity;
  DateTime? _lastTouch;
  Timer? _idle;
  Timer? _trailingTouch;
  bool _touching = false;
  bool _disposed = false;
  int _generation = 0;

  bool get unlocked => _token != null && _expiresAt != null && _expiresAt!.isAfter(DateTime.now())
      && _lastActivity != null && DateTime.now().difference(_lastActivity!) < const Duration(minutes: 5);
  String? get token => unlocked ? _token : null;

  Future<void> verify(String pin) async {
    if (_token != null) await lock();
    final generation = _generation;
    final data = await _call('verify', body: {'pin': pin});
    if (_disposed || generation != _generation) return;
    final rawToken = data['unlockToken'];
    final expiry = data['expiresAt'] is String ? DateTime.tryParse(data['expiresAt'] as String) : null;
    if (rawToken is! String || !RegExp(r'^par_[0-9a-f]{64}$').hasMatch(rawToken) || expiry == null || !expiry.isAfter(DateTime.now())) {
      throw const ParentAccessException('Não foi possível confirmar o desbloqueio. Tenta novamente.');
    }
    _token = rawToken; _expiresAt = expiry; _lastActivity = DateTime.now(); _lastTouch = DateTime.now();
    _scheduleIdle(); notifyListeners();
  }

  void activity() {
    if (!unlocked) {if (_token != null) forget(); return;}
    final now = DateTime.now();
    if (_lastActivity != null && now.difference(_lastActivity!) < const Duration(seconds: 1)) return;
    _lastActivity = now; _scheduleIdle();
    _trailingTouch?.cancel();
    if (_lastTouch == null || now.difference(_lastTouch!) >= const Duration(seconds: 30)) {
      _touch();
    } else {
      _trailingTouch = Timer(const Duration(seconds: 3), _touch);
    }
  }

  void _scheduleIdle() {
    _idle?.cancel();
    final remaining = _lastActivity!.add(const Duration(minutes: 5)).difference(DateTime.now());
    _idle = Timer(remaining.isNegative ? Duration.zero : remaining, () {lock();});
  }

  Future<void> _touch() async {
    if (!unlocked || _touching) return;
    final generation = _generation;
    _touching = true;
    try {
      final data = await _call('touch');
      if (_disposed || generation != _generation) return;
      final expiry = data['expiresAt'] is String ? DateTime.tryParse(data['expiresAt'] as String) : null;
      if (expiry == null || !expiry.isAfter(DateTime.now())) {forget(); return;}
      _expiresAt = expiry; _lastTouch = DateTime.now();
    } catch (_) {if (!_disposed && generation == _generation) forget();}
    finally {_touching = false;}
  }

  Future<void> check() async {
    if (!unlocked) {forget(); return;}
    final generation = _generation;
    try {
      await _call('unlock-status', method: HttpMethod.get);
    } catch (_) {if (!_disposed && generation == _generation) forget();}
  }

  Future<void> lock() async {
    final oldToken = _token;
    forget();
    if (oldToken != null) {
      try {await _call('revoke', overrideToken: oldToken);} catch (_) {
        // Local capability is erased immediately; server expiry remains the fallback offline.
      }
    }
  }

  void forget() {
    _generation++; _token = null; _expiresAt = null; _lastActivity = null; _lastTouch = null;
    _idle?.cancel(); _trailingTouch?.cancel();
    if (!_disposed) notifyListeners();
  }

  Future<Map> _call(String operation, {Map<String, dynamic>? body, HttpMethod method = HttpMethod.post, String? overrideToken}) async {
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null) throw const ParentAccessException('A tua sessão terminou. Entra novamente na conta.');
      final capability = overrideToken ?? _token;
      final response = await client.functions.invoke('parent-pin/v1/$operation', method: method,
        body: method == HttpMethod.get ? null : body ?? <String,dynamic>{},
        headers: {'Authorization':'Bearer ${session.accessToken}', if (capability != null) 'X-Parent-Unlock':capability});
      if (response.data is! Map) throw const ParentAccessException('Não foi possível confirmar o pedido.');
      return response.data as Map;
    } on ParentAccessException {rethrow;}
    on FunctionException catch (error) {
      final data = error.details;
      final payload = data is Map ? data['error'] : null;
      final message = payload is Map ? payload['message'] : null;
      final details = payload is Map ? payload['details'] : null;
      final retry = details is Map ? details['retryAfter'] : null;
      throw ParentAccessException(message is String ? message : 'Não foi possível desbloquear a área do responsável.',
        retryAfter: retry is num && retry > 0 ? retry.ceil() : null);
    } catch (_) {throw const ParentAccessException('Não foi possível ligar ao serviço. Tenta novamente.');}
  }

  @override
  void dispose() {_disposed = true; forget(); super.dispose();}
}
