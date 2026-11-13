import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/family/domain/family_models.dart';
import 'package:escola_em_dia/features/family/presentation/child_profile_page.dart';
import 'package:escola_em_dia/features/family/presentation/widgets/ready_children_grid.dart';

void main() {
  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {await tester.tap(find.text(digit)); await tester.pump();}
  }

  testWidgets('criação do perfil em dois passos: identificação e depois PIN', (tester) async {
    setSize(tester, const Size(800, 4000));
    final drafts = <ChildProfileDraft>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ChildProfilePage(
      onSave: (draft) async {
        drafts.add(draft);
        return ChildProfile(id: 'c1', familyId: 'f1', displayName: draft.displayName,
          schoolYear: draft.schoolYear, avatarId: draft.avatarId);
      },
      onSaved: (_) {}, onBack: () {},
    )));

    // Passo 1: só a identificação, sem PIN.
    expect(find.text('PASSO 3 DE 5 • PERFIL'), findsOneWidget);
    expect(find.text('PIN Infantil (4 Dígitos)'), findsNothing);
    await tester.tap(find.text('Continuar para o PIN Infantil'));
    await tester.pumpAndSettle();
    expect(find.text('Indica a alcunha da criança.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Tomás');
    await tester.tap(find.text('Continuar para o PIN Infantil'));
    await tester.pumpAndSettle();

    // Passo 2: PIN, com resumo da criança e sem o formulário.
    expect(find.text('PASSO 4 DE 5 • PIN INFANTIL'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Tomás'), findsOneWidget);
    await typePin(tester, '2468');
    await tester.tap(find.text('Continuar e confirmar PIN'));
    await tester.pumpAndSettle();
    await typePin(tester, '2468');
    await tester.tap(find.text('Guardar Perfil & Avançar'));
    await tester.pumpAndSettle();

    expect(drafts.single.displayName, 'Tomás');
    expect(drafts.single.pin, '2468');
  });

  testWidgets('voltar no passo do PIN regressa à identificação com os dados', (tester) async {
    setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ChildProfilePage(
      onSave: (_) async => throw UnimplementedError(), onSaved: (_) {}, onBack: () {},
    )));
    await tester.enterText(find.byType(TextFormField), 'Inês');
    await tester.tap(find.text('Continuar para o PIN Infantil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Inês'), findsOneWidget);
  });

  for (final width in [390.0, 1140.0]) {
    testWidgets('grelha «Tudo a postos» funciona a ${width.toInt()} px', (tester) async {
      setSize(tester, Size(width, 2400));
      final entered = <String>[], prepared = <String>[];
      var added = 0;
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: ReadyChildrenGrid(
          children: const [
            ChildProfile(id: 'a', familyId: 'f', displayName: 'Ana', schoolYear: 2, avatarId: 'fox'),
            ChildProfile(id: 'b', familyId: 'f', displayName: 'Bruno', schoolYear: 4, avatarId: 'owl'),
          ],
          highlightedChildId: 'b',
          onEnterChild: entered.add, onPrepareWorksheet: prepared.add, onAddChild: () => added++,
        )),
      ))));
      expect(tester.takeException(), isNull);
      expect(find.text('Entrar na área da criança'), findsNWidgets(2));
      expect(find.text('Novo'), findsOneWidget);

      await tester.tap(find.text('Preparar uma ficha').last);
      await tester.tap(find.text('Entrar na área da criança').first);
      await tester.tap(find.text('Adicionar criança'));
      expect(prepared, ['b']);
      expect(entered, ['a']);
      expect(added, 1);
    });
  }
}
