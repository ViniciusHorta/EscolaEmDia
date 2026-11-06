import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/legal/data/legal_service.dart';
import 'package:escola_em_dia/features/legal/domain/legal_models.dart';
import 'package:escola_em_dia/features/legal/presentation/legal_consent_gate.dart';
import 'package:escola_em_dia/features/legal/presentation/legal_document_page.dart';

void main() {
  final terms = LegalDocument(id: 't2', kind: LegalDocumentKind.terms, version: 2, title: 'Termos',
    content: '# Termos\n\nTexto **importante**.\n\n- item', publishedAt: DateTime(2026, 11, 6),
    changeSummary: 'Novo prazo de conservação.');
  final privacy = LegalDocument(id: 'p1', kind: LegalDocumentKind.privacy, version: 1, title: 'Privacidade',
    content: 'Texto', publishedAt: DateTime(2026, 11, 1));

  Future<List<List<String>>> pump(WidgetTester tester, {List<LegalAcceptance> accepted = const [],
      Object? error}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <List<String>>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: LegalConsentPage(
      documents: [terms, privacy],
      accepted: accepted,
      onAccept: (ids) async { calls.add(ids); if (error != null) throw error; },
      onReload: () {},
      onSignOut: () async {},
    )));
    return calls;
  }

  testWidgets('primeiro aceite exige a caixa e envia as versões em vigor', (tester) async {
    final calls = await pump(tester);
    expect(find.text('Antes de continuar'), findsOneWidget);
    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pump();
    expect(calls, isEmpty);
    expect(find.text('Aceita os documentos para continuar.'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pumpAndSettle();
    expect(calls.single, ['t2', 'p1']);
  });

  testWidgets('nova versão mostra o resumo das alterações', (tester) async {
    await pump(tester, accepted: [LegalAcceptance(documentId: 't1', kind: LegalDocumentKind.terms, version: 1,
      acceptedAt: DateTime(2026, 1, 1))]);
    expect(find.text('Atualizámos os nossos documentos'), findsOneWidget);
    expect(find.text('O que mudou'), findsOneWidget);
    expect(find.text('Novo prazo de conservação.'), findsOneWidget);
  });

  testWidgets('versão desatualizada mostra a mensagem e permite recarregar', (tester) async {
    await pump(tester, error: const LegalException('Há uma versão mais recente.', outdated: true));
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Aceitar e continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Há uma versão mais recente.'), findsOneWidget);
    expect(find.text('Ver a versão mais recente'), findsOneWidget);
  });

  testWidgets('documento abre com título, versão e conteúdo', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: LegalDocumentPage(document: terms)));
    expect(find.text('Termos de Utilização'), findsOneWidget);
    expect(find.text('Versão 2 • em vigor desde 06/11/2026'), findsOneWidget);
    expect(find.text('item'), findsOneWidget);
  });

  test('estado ignora entradas inválidas', () {
    final status = LegalStatus.tryParse({
      'current': [{'id': 'x', 'kind': 'terms', 'version': 1, 'title': 'T', 'content': 'c', 'publishedAt': '2026-11-06T10:00:00Z'}],
      'pending': [{'id': 'y', 'kind': 'outro'}],
      'accepted': [],
    })!;
    expect(status.current, hasLength(1));
    expect(status.compliant, isTrue);
  });
}
