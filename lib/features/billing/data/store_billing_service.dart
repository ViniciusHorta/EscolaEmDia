import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'billing_service.dart';

/// Compras nas lojas: Google Play (Android) e App Store (iOS). O servidor escolhe o produto-vaga
/// (premium_crianca_N) e verifica cada compra na API da loja antes de ativar o Premium; só depois a
/// compra é concluída aqui (completePurchase / finishTransaction).
class StoreBillingService {
  StoreBillingService(this.billing, {required this.onMessage, required this.onPremiumChanged});
  final BillingService billing;
  final void Function(String message) onMessage;
  final VoidCallback onPremiumChanged;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  static const packageName = 'com.escolaemdia.app';
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get supported => isAndroid || isIOS;

  /// Canal das assinaturas compradas nesta plataforma ('google_play' / 'app_store').
  static String? get channel => isAndroid ? 'google_play' : isIOS ? 'app_store' : null;
  static String get storeName => isIOS ? 'App Store' : 'Google Play';

  /// Ouve as compras desde o arranque: compras interrompidas são entregues de novo aqui.
  void start() {
    if (!supported || _subscription != null) return;
    _subscription = InAppPurchase.instance.purchaseStream.listen(_handle,
      onError: (Object _) => onMessage('Não foi possível comunicar com a $storeName.'));
  }

  void dispose() => _subscription?.cancel();

  /// Abre a folha de compra da loja. Devolve uma mensagem de erro ou null.
  Future<String?> buy(String childId) async {
    try {
      if (!await InAppPurchase.instance.isAvailable()) return 'A $storeName não está disponível neste dispositivo.';
      final offer = isIOS ? await billing.appleOffer(childId) : await billing.playOffer(childId);
      final response = await InAppPurchase.instance.queryProductDetails({offer.productId});
      if (response.productDetails.isEmpty) return 'O Premium ainda não está disponível na $storeName.';
      // Android: obfuscatedAccountId; iOS: appAccountToken (UUID). Em ambos = id da família.
      final started = await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(
        productDetails: response.productDetails.first, applicationUserName: offer.accountId));
      return started ? null : 'Não foi possível iniciar a compra.';
    } on BillingException catch (failure) {
      if (failure.code == 'CHILD_ALREADY_PREMIUM') onPremiumChanged(); // lista desatualizada: recarregar
      return failure.message;
    } catch (_) {
      return 'Não foi possível iniciar a compra na $storeName.';
    }
  }

  /// iOS: volta a entregar as compras desta conta Apple (exigido pela App Store). O servidor
  /// liga-as à família pelo appAccountToken.
  Future<void> restore() async {
    if (!isIOS) return;
    try {
      await InAppPurchase.instance.restorePurchases();
      onMessage('A verificar compras anteriores…');
    } catch (_) {
      onMessage('Não foi possível restaurar as compras. Tenta novamente.');
    }
  }

  /// Página de gestão da assinatura na loja (cancelar, trocar o meio de pagamento).
  static Uri manageUrl(String? productId) => isIOS
    ? Uri.parse('https://apps.apple.com/account/subscriptions')
    : Uri.https('play.google.com', '/store/account/subscriptions',
        {if (productId != null) 'sku': productId, 'package': packageName});

  // Recusas definitivas: concluir a transação (senão a loja volta a entregá-la em cada arranque).
  // Android: concluir também confirma a compra na Google, por isso só depois de o servidor a recusar
  // e reembolsar. iOS: concluir só tira a transação da fila; o estado vem sempre do servidor.
  static const _finalAndroid = {'PURCHASE_REFUSED', 'CHILD_ALREADY_PREMIUM'};
  static const _finalIOS = {'CHILD_ALREADY_PREMIUM', 'PURCHASE_NOT_LINKED', 'FAMILY_NOT_FOUND'};

  Future<String?> _verify(PurchaseDetails purchase) async {
    if (isIOS) {
      final id = purchase.purchaseID;
      if (id == null) throw const BillingException('Compra sem identificador.', code: 'INVALID_REQUEST');
      return billing.verifyAppleTransaction(id);
    }
    return billing.verifyPlayPurchase(purchase.productID, purchase.verificationData.serverVerificationData);
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      var complete = false;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onMessage('Pagamento pendente. O Premium fica ativo quando a $storeName o confirmar.');
        case PurchaseStatus.canceled:
          onMessage('Compra cancelada. Não foi cobrado nada.');
          complete = true;
        case PurchaseStatus.error:
          onMessage('A compra não foi concluída. Tenta novamente.');
          complete = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            final plan = await _verify(purchase);
            if (purchase.status == PurchaseStatus.purchased) {
              onMessage(plan == 'premium' ? 'Premium ativo 🎉' : 'Compra recebida. O Premium fica ativo dentro de instantes.');
            }
            onPremiumChanged();
            complete = true;
          } on BillingException catch (failure) {
            // Restaurar entrega todas as compras antigas: só avisar das compras novas.
            if (purchase.status == PurchaseStatus.purchased) onMessage(failure.message);
            onPremiumChanged(); // o servidor pode já ter ativado o Premium (ex.: pela notificação da loja)
            // Recusa definitiva: concluir. Falha temporária: não concluir, a compra volta a ser entregue
            // e as notificações da loja também a sincronizam.
            complete = (isIOS ? _finalIOS : _finalAndroid).contains(failure.code)
              || (isIOS && purchase.status == PurchaseStatus.restored);
          }
      }
      if (complete && purchase.pendingCompletePurchase) {
        try {await InAppPurchase.instance.completePurchase(purchase);} catch (_) {/* volta a ser entregue */}
      }
    }
  }
}
