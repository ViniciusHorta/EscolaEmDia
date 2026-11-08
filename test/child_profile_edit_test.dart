import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/family/domain/family_models.dart';
import 'package:escola_em_dia/features/family/presentation/child_profile_page.dart';

void main() {
  const child = ChildProfile(id: 'c1', familyId: 'f1', displayName: 'Rita', schoolYear: 2, avatarId: 'owl');

  Future<List<ChildProfileUpdate>> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final updates = <ChildProfileUpdate>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: ChildProfilePage.edit(
      child: child,
      onUpdate: (update) async {
        updates.add(update);
        return ChildProfile(id: child.id, familyId: child.familyId, displayName: update.displayName,
          schoolYear: update.schoolYear, avatarId: update.avatarId);
      },
      onSaved: (_) {}, onBack: () {},
    )));
    return updates;
  }

  testWidgets('edição pré-preenche o perfil e guarda sem alterar o PIN', (tester) async {
    final updates = await pump(tester);
    expect(find.widgetWithText(TextFormField, 'Rita'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Rita Maria');
    await tester.tap(find.text('Guardar alterações'));
    await tester.pumpAndSettle();
    expect(updates, hasLength(1));
    expect(updates.single.displayName, 'Rita Maria');
    expect(updates.single.schoolYear, 2);
    expect(updates.single.avatarId, 'owl');
    expect(updates.single.pin, isNull);
  });

  testWidgets('permite escolher anos do 2.º e 3.º ciclos', (tester) async {
    final updates = await pump(tester);
    expect(find.text('1.º Ciclo'), findsOneWidget);
    expect(find.text('2.º Ciclo'), findsOneWidget);
    expect(find.text('3.º Ciclo'), findsOneWidget);
    // Só os anos do ciclo selecionado (o do ano atual da criança) são mostrados.
    expect(find.text('2.º Ano de Escolaridade'), findsOneWidget);
    expect(find.text('9.º Ano de Escolaridade'), findsNothing);
    await tester.ensureVisible(find.text('3.º Ciclo'));
    await tester.tap(find.text('3.º Ciclo'));
    await tester.pump();
    expect(find.text('1.º Ano de Escolaridade'), findsNothing);
    expect(updates, isEmpty);
    await tester.ensureVisible(find.text('9.º Ano de Escolaridade'));
    await tester.tap(find.text('9.º Ano de Escolaridade'));
    await tester.tap(find.text('Guardar alterações'));
    await tester.pumpAndSettle();
    expect(updates.single.schoolYear, 9);
  });

  testWidgets('alterar PIN exige confirmação e envia o novo PIN', (tester) async {
    final updates = await pump(tester);
    await tester.tap(find.text('Alterar PIN'));
    await tester.pumpAndSettle();
    for (final digit in ['5', '6', '7', '8']) {await tester.tap(find.text(digit)); await tester.pump();}
    await tester.tap(find.text('Continuar e confirmar PIN'));
    await tester.pumpAndSettle();
    for (final digit in ['5', '6', '7', '8']) {await tester.tap(find.text(digit)); await tester.pump();}
    await tester.tap(find.text('Guardar alterações'));
    await tester.pumpAndSettle();
    expect(updates.single.pin, '5678');
  });
}
