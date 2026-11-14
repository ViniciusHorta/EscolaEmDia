import 'package:escola_em_dia/features/billing/domain/billing_models.dart';
import 'package:escola_em_dia/features/billing/presentation/premium_paywall.dart';
import 'package:escola_em_dia/features/family/domain/family_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Free: quotas do responsável e da criança', () {
    final access = ChildDailyAccess.tryParse({'plan': 'free', 'assignmentsToday': 1, 'assignmentLimit': 1,
      'attemptsToday': 0, 'attemptLimit': 1, 'freeMaxQuestions': 6})!;
    expect(access.isFree, isTrue);
    expect(access.assignmentQuotaReached, isTrue);
    expect(access.attemptQuotaReached, isFalse);
    expect(access.withNewAttempt().attemptQuotaReached, isTrue);
  });

  test('Premium: sem limites (limites null)', () {
    final access = ChildDailyAccess.tryParse({'plan': 'premium', 'assignmentsToday': 9, 'attemptsToday': 9,
      'assignmentLimit': null, 'attemptLimit': null})!;
    expect(access.assignmentQuotaReached, isFalse);
    expect(access.attemptQuotaReached, isFalse);
  });

  test('Locked não pode receber fichas; resposta inválida é ignorada', () {
    expect(ChildDailyAccess.tryParse({'plan': 'locked'})!.assignmentQuotaReached, isTrue);
    expect(ChildDailyAccess.tryParse(null), isNull);
    expect(ChildDailyAccess.tryParse({'assignmentsToday': 1}), isNull);
  });

  test('Códigos do servidor mapeiam para o motivo da oferta', () {
    expect(paywallReasonForCode('DAILY_ASSIGNMENT_LIMIT_REACHED'), PaywallReason.dailyLimit);
    expect(paywallReasonForCode('PREMIUM_WORKSHEET_REQUIRED'), PaywallReason.premiumWorksheet);
    expect(paywallReasonForCode('CHILD_PLAN_LOCKED'), PaywallReason.locked);
    expect(paywallReasonForCode('INVALID_REQUEST'), isNull);
  });

  test('Resumo da assinatura da criança', () {
    final child = ChildProfile.fromJson({'id': 'c', 'familyId': 'f', 'displayName': 'Ana', 'schoolYear': 2, 'avatarId': 'owl',
      'plan': 'premium', 'subscription': {'channel': 'stripe', 'status': 'in_grace', 'autoRenew': true,
        'currentPeriodEnd': '2026-12-01T00:00:00Z'}});
    expect(child.isPremium, isTrue);
    expect(child.subscription!.isStripe && child.subscription!.inGrace, isTrue);
    expect(ChildProfile.fromJson({'id': 'c', 'familyId': 'f', 'displayName': 'A', 'schoolYear': 1, 'avatarId': 'owl'}).subscription, isNull);
  });

  testWidgets('Oferta mostra motivo, preço e aviso de pagamento em breve', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showPremiumPaywall(context, childName: 'Ana', reason: PaywallReason.dailyLimit, freeMaxQuestions: 6),
      child: const Text('abrir'))))));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Ana já recebeu a ficha de hoje'), findsOneWidget);
    expect(find.text(premiumPriceLabel), findsOneWidget);
    expect(find.text('Fichas com mais de 6 perguntas'), findsOneWidget);
    await tester.ensureVisible(find.text('Ativar Premium para Ana'));
    await tester.tap(find.text('Ativar Premium para Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Pagamento em breve'), findsOneWidget);
  });

  testWidgets('Com pagamento disponível, mostra o erro devolvido', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => showPremiumPaywall(context, childName: 'Ana', reason: PaywallReason.locked,
        onSubscribe: () async => 'Os pagamentos estão temporariamente indisponíveis.'),
      child: const Text('abrir'))))));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ativar Premium para Ana'));
    await tester.tap(find.text('Ativar Premium para Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Os pagamentos estão temporariamente indisponíveis.'), findsOneWidget);
  });
}
