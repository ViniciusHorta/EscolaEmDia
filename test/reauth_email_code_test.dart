import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/account/data/account_service.dart';
import 'package:escola_em_dia/features/account/presentation/delete_account_page.dart';
import 'package:escola_em_dia/features/parent_pin/data/parent_access_service.dart';
import 'package:escola_em_dia/features/parent_pin/data/parent_pin_service.dart';
import 'package:escola_em_dia/features/parent_pin/presentation/parent_pin_reset_page.dart';

SupabaseClient fakeClient() => SupabaseClient('http://localhost:1', 'k',
    authOptions: const AuthClientOptions(autoRefreshToken: false));

/// Conta criada com o Google: sem palavra-passe.
class GooglePinService extends ParentPinService {
  GooglePinService({this.wrongCode = false}) : super(fakeClient());
  final bool wrongCode;
  final calls = <String>[];

  @override
  bool get hasPassword => false;
  @override
  Future<void> sendReauthCode() async => calls.add('send');
  @override
  Future<void> reauthenticateWithCode(String code) async {
    calls.add('code:$code');
    if (wrongCode) throw const ParentPinException('O código não está correto ou expirou. Confirma o código ou pede um novo.');
  }
  @override
  Future<void> reauthenticate(String password) async => calls.add('password');
  @override
  Future<void> reset(String pin) async => calls.add('reset:$pin');
}

class FakeAccess extends ParentAccessService {
  FakeAccess() : super(fakeClient());
  @override
  Future<void> verify(String pin) async {}
}

class GoogleAccountService extends AccountService {
  GoogleAccountService() : super(fakeClient());
  final calls = <String>[];

  @override
  bool get hasPassword => false;
  @override
  Future<void> sendReauthCode() async => calls.add('send');
  @override
  Future<void> reauthenticateWithCode(String code) async => calls.add('code:$code');
  @override
  Future<void> reauthenticate(String password) async => calls.add('password');
  @override
  Future<void> deleteAccount() async => calls.add('delete');
}

void main() {
  void setSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {await tester.tap(find.text(digit)); await tester.pump();}
  }

  testWidgets('conta Google redefine o PIN com código por e-mail', (tester) async {
    setSize(tester);
    final service = GooglePinService();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: ParentPinResetPage(service: service, access: FakeAccess())));

    // Sem palavra-passe: não há campo nem opção de palavra-passe.
    expect(find.text('Palavra-passe da conta'), findsNothing);
    expect(find.text('Usar a palavra-passe'), findsNothing);

    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(service.calls, ['send']);
    expect(find.textContaining('Reenviar código ('), findsOneWidget, reason: 'reenvio em espera');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text('Confirmar código'));
    await tester.pumpAndSettle();
    expect(service.calls, ['send', 'code:123456']);

    await typePin(tester, '1357');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await typePin(tester, '1357');
    await tester.tap(find.text('Guardar novo PIN'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'reset:1357');
    expect(service.calls, isNot(contains('password')));

    // Deixa o temporizador do reenvio terminar.
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('código errado mostra o erro e não avança', (tester) async {
    setSize(tester);
    final service = GooglePinService(wrongCode: true);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light,
      home: ParentPinResetPage(service: service, access: FakeAccess())));
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.text('Confirmar código'));
    await tester.pumpAndSettle();
    expect(find.text('O código não está correto ou expirou. Confirma o código ou pede um novo.'), findsOneWidget);
    expect(find.text('Confirma que és tu'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('conta Google elimina a conta com código por e-mail', (tester) async {
    setSize(tester);
    final service = GoogleAccountService();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () => DeleteAccountPage.open(context, service), child: const Text('abrir'))),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Palavra-passe da conta'), findsNothing);
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '654321');
    await tester.enterText(find.byType(TextField).at(1), 'ELIMINAR');
    await tester.pump();
    await tester.tap(find.text('Eliminar conta definitivamente'));
    await tester.pumpAndSettle();
    expect(service.calls, ['send', 'code:654321', 'delete']);
    await tester.pump(const Duration(seconds: 61));
  });
}
