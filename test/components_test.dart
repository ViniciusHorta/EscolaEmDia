import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/features/component_gallery/component_gallery_page.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/shared/widgets/app_button.dart';
import 'package:escola_em_dia/shared/widgets/cards/profile_card.dart';
import 'package:escola_em_dia/shared/widgets/pin/app_pin_input.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
      );

  testWidgets(
      'PIN limita os dígitos, permite apagar e limpar e notifica ao completar',
      (tester) async {
    var value = '';
    final completed = <String>[];
    await tester.pumpWidget(host(AppPinInput(
        label: 'PIN infantil',
        onChanged: (pin) => value = pin,
        onCompleted: completed.add)));
    for (final digit in ['1', '2', '3', '4', '5']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(value, '1234');
    expect(completed, ['1234']);
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(value, '123');
    await tester.tap(find.byIcon(Icons.clear_all_rounded));
    await tester.pump();
    expect(value, '');
    await tester.enterText(find.byType(TextField), 'a12b345');
    await tester.pump();
    expect(value, '1234');
    expect(completed, ['1234', '1234']);
  });

  testWidgets('PIN desativado e botões indisponíveis não executam ações',
      (tester) async {
    var called = false;
    await tester
        .pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
      AppPinInput(
          label: 'PIN', enabled: false, onChanged: (_) => called = true),
      AppButton(
          label: 'A guardar', loading: true, onPressed: () => called = true),
      const AppButton(label: 'Indisponível', onPressed: null),
    ])));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('A guardar'));
    await tester.tap(find.text('Indisponível'));
    expect(called, false);
  });

  for (final width in [390.0, 1140.0]) {
    testWidgets(
        'galeria permite selecionar perfis e funciona a ${width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const ComponentGalleryPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final profile = find.widgetWithText(ProfileCard, 'Leonor');
      await tester.ensureVisible(profile);
      await tester.pumpAndSettle();
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(tester.widget<ProfileCard>(profile).selected, true);
      final pin = find.byType(AppPinInput);
      await tester.ensureVisible(pin);
      await tester.pumpAndSettle();
      expect(find.text('PIN de Leonor'), findsOneWidget);
      final lastCard = find.text('Português: Sinónimos');
      await tester.ensureVisible(lastCard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
