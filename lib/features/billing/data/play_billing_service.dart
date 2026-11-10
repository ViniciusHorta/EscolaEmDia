import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing_service.dart';

/// Compras Google Play (Android). O servidor escolhe o produto-vaga (premium_crianca_N) e
/// verifica cada compra na API da Google antes de ativar o Premium; só depois a compra é
/// concluída aqui (completePurchase), para a Google não a reembolsar.
class PlayBillingService {
  PlayBillingService(this.billing, {required this.onMessage, required this.onPremiumChanged});
  final BillingService billing;
  final void Function(String message) onMessage;
  final VoidCallback onPremiumChanged;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  static const packageName = 'com.escolaemdia.app';
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Ouve as compras desde o arranque: compras interrompidas são entregues de novo aqui.
  void start() {
    if (!supported || _subscription != null) return;
    _subscription = InAppPurchase.instance.purchaseStream.listen(_handle,
      onError: (Object _) => onMessage('Não foi possível comunicar com a Google Play.'));
  }

  void dispose() => _subscription?.cancel();

  /// Abre a folha de compra da Google Play. Devolve uma mensagem de erro ou null.
  Future<String?> buy(String childId) async {
    try {
      if (!await InAppPurchase.instance.isAvailable()) return 'A Google Play não está disponível neste dispositivo.';
      final offer = await billing.playOffer(childId);
      final response = await InAppPurchase.instance.queryProductDetails({offer.productId});
      if (response.productDetails.isEmpty) return 'O Premium ainda não está disponível na Google Play.';
      final started = await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(
        productDetails: response.productDetails.first, applicationUserName: offer.accountId));
      return started ? null : 'Não foi possível iniciar a compra.';
    } on BillingException catch (failure) {
      if (failure.code == 'CHILD_ALREADY_PREMIUM') onPremiumChanged(); // lista desatualizada: recarregar
      return failure.message;
    } catch (_) {
      return 'Não foi possível iniciar a compra na Google Play.';
    }
  }

  /// Página de gestão da assinatura na Play Store (cancelar, trocar cartão).
  static Uri manageUrl(String? productId) => Uri.https('play.google.com', '/store/account/subscriptions',
    {if (productId != null) 'sku': productId, 'package': packageName});

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      var complete = false;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onMessage('Pagamento pendente. O Premium fica ativo quando a Google Play o confirmar.');
        case PurchaseStatus.canceled:
          onMessage('Compra cancelada. Não foi cobrado nada.');
          complete = true;
        case PurchaseStatus.error:
          onMessage('A compra não foi concluída. Tenta novamente.');
          complete = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            final plan = await billing.verifyPlayPurchase(purchase.productID, purchase.verificationData.serverVerificationData);
            onMessage(plan == 'premium' ? 'Premium ativo 🎉' : 'Compra recebida. O Premium fica ativo dentro de instantes.');
            onPremiumChanged();
            complete = true;
          } on BillingException catch (failure) {
            onMessage(failure.message);
            onPremiumChanged(); // o servidor pode já ter ativado o Premium (ex.: pela notificação da Google)
            // Recusa definitiva (já reembolsada no servidor): concluir. Falha temporária: não concluir,
            // a compra volta a ser entregue e as notificações da Google também a sincronizam.
            complete = failure.code == 'PURCHASE_REFUSED' || failure.code == 'CHILD_ALREADY_PREMIUM';
          }
      }
      if (complete && purchase.pendingCompletePurchase) {
        try {await InAppPurchase.instance.completePurchase(purchase);} catch (_) {/* volta a ser entregue */}
      }
    }
  }
}
