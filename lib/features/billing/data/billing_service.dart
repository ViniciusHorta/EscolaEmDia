import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/request_id.dart';

class BillingException implements Exception {
  const BillingException(this.message, {this.code});
  final String message;
  final String? code;
}

/// Pagamentos Web (Stripe Checkout e portal de gestão). Só na área do responsável.
/// O Premium é ativado pelo webhook do Stripe; o regresso do checkout só mostra o estado.
class BillingService {
  const BillingService(this.client, {required this.parentToken, required this.onParentLocked});
  final SupabaseClient client;
  final String? Function() parentToken;
  final void Function() onParentLocked;

  /// URL do Stripe Checkout para tornar a criança Premium.
  Future<Uri> checkoutUrl(String childId) async =>
      _url(await _post('/v1/children/$childId/checkout', {'clientRequestId': newRequestId()}));

  /// URL do portal do Stripe (cancelar, trocar cartão, faturas).
  Future<Uri> portalUrl(String familyId) async => _url(await _post('/v1/families/$familyId/portal', const {}));

  /// Android: produto-vaga a comprar e identificador da família (obfuscatedAccountId).
  Future<({String productId, String accountId})> playOffer(String childId) async {
    final data = await _post('/v1/children/$childId/play/offer', const {});
    final productId = data['productId'], accountId = data['obfuscatedAccountId'];
    if (productId is! String || accountId is! String) throw const BillingException('Não foi possível preparar a compra.');
    return (productId: productId, accountId: accountId);
  }

  /// Android: verifica a compra no servidor (API Google Play) e ativa o Premium. Devolve o plano.
  Future<String?> verifyPlayPurchase(String productId, String purchaseToken) async =>
      (await _post('/v1/play/purchases', {'productId': productId, 'purchaseToken': purchaseToken}))['plan'] as String?;

  Uri _url(Map data) {
    final url = Uri.tryParse('${data['url']}');
    if (url == null || url.scheme != 'https' || !url.host.endsWith('stripe.com')) {
      throw const BillingException('Não foi possível abrir o pagamento. Tenta novamente.');
    }
    return url;
  }

  Future<Map> _post(String path, Map<String, dynamic> body) async {
    try {
      var session = client.auth.currentSession;
      if (session?.isExpired == true) session = (await client.auth.refreshSession()).session;
      if (session == null) throw const BillingException('A tua sessão terminou. Entra novamente na conta.');
      final capability = parentToken();
      if (capability == null) {onParentLocked(); throw const BillingException('Desbloqueia a área do responsável para continuar.');}
      final response = await client.functions.invoke('billing$path', method: HttpMethod.post, body: body,
        headers: {'Authorization': 'Bearer ${session.accessToken}', 'X-Parent-Unlock': capability});
      if (response.data is! Map) throw const BillingException('Não foi possível confirmar o pedido.');
      return response.data as Map;
    } on BillingException {rethrow;}
    on FunctionException catch (error) {
      final data = error.details; final payload = data is Map ? data['error'] : null;
      if (payload is Map && payload['code'] == 'PARENT_LOCKED') onParentLocked();
      throw BillingException(payload is Map && payload['message'] is String ? payload['message'] as String : 'Não foi possível abrir o pagamento.',
        code: payload is Map && payload['code'] is String ? payload['code'] as String : null);
    } catch (_) {throw const BillingException('Não foi possível ligar ao serviço. Tenta novamente.');}
  }
}
