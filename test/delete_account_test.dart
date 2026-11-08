import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/account/data/account_service.dart';
import 'package:escola_em_dia/features/account/presentation/delete_account_page.dart';

class FakeAccountService extends AccountService {
  FakeAccountService({this.wrongPassword = false, this.deleteError})
      : super(SupabaseClient('http://localhost:1', 'k',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final bool wrongPassword;
  final AccountException? deleteError;
  final calls = <String>[];

  @override
  Future<void> reauthenticate(String password) async {
    calls.add('reauth:$password');
    if (wrongPassword) throw const AccountException('A palavra-passe não está correta.');
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    if (deleteError != null) throw deleteError!;
  }
}

void main() {
  Future<List<bool?>> pump(WidgetTester tester, FakeAccountService service) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <bool?>[];
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () async => results.add(await DeleteAccountPage.open(context, service)),
        child: const Text('abrir'),
      )),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> goToConfirm(WidgetTester tester) async {
    expect(find.text('O que é apagado'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }

  Finder deleteButton() => find.text('Eliminar conta definitivamente');

  testWidgets('só elimina depois da palavra-passe e de escrever ELIMINAR', (tester) async {
    final service = FakeAccountService();
    final results = await pump(tester, service);
    await goToConfirm(tester);

    await tester.enterText(find.byType(TextField).at(0), 'segredo');
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty, reason: 'sem ELIMINAR o botão está desativado');

    await tester.enterText(find.byType(TextField).at(1), 'eliminar');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(service.calls, ['reauth:segredo', 'delete']);
    expect(results, [true]);
    expect(find.text('A tua conta e os dados da família foram eliminados.'), findsOneWidget);
  });

  testWidgets('palavra-passe errada não chama a eliminação', (tester) async {
    final service = FakeAccountService(wrongPassword: true);
    final results = await pump(tester, service);
    await goToConfirm(tester);
    await tester.enterText(find.byType(TextField).at(0), 'errada');
    await tester.enterText(find.byType(TextField).at(1), 'ELIMINAR');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(service.calls, ['reauth:errada']);
    expect(find.text('A palavra-passe não está correta.'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('erro do servidor fica no ecrã e permite tentar de novo', (tester) async {
    final service = FakeAccountService(
        deleteError: const AccountException('Não foi possível eliminar a conta. Tenta novamente dentro de momentos.'));
    await pump(tester, service);
    await goToConfirm(tester);
    await tester.enterText(find.byType(TextField).at(0), 'segredo');
    await tester.enterText(find.byType(TextField).at(1), 'ELIMINAR');
    await tester.pump();
    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível eliminar a conta. Tenta novamente dentro de momentos.'), findsOneWidget);
    expect(deleteButton(), findsOneWidget);
  });

  testWidgets('«Manter a conta» fecha sem eliminar', (tester) async {
    final service = FakeAccountService();
    final results = await pump(tester, service);
    await tester.tap(find.text('Manter a conta'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(service.calls, isEmpty);
  });
}
