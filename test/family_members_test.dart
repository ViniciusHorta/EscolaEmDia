import 'package:escola_em_dia/core/theme/area_palette.dart';
import 'package:escola_em_dia/features/family/data/pending_invitation_store.dart';
import 'package:escola_em_dia/features/family/domain/family_models.dart';
import 'package:escola_em_dia/features/family/presentation/parent_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final token = 'inv_${'a' * 64}';

  test('FamilyMembers lê responsáveis, convites e o limite de 4', () {
    final data = FamilyMembers.fromJson({
      'members': [
        {'adultUserId': 'u1', 'email': 'a@x.pt', 'joinedAt': '2026-11-01T10:00:00Z', 'isMe': true},
        {'adultUserId': 'u2', 'email': 'b@x.pt', 'joinedAt': '2026-11-02T10:00:00Z', 'isMe': false},
      ],
      'invitations': [
        {'id': 'i1', 'email': 'c@x.pt', 'createdAt': '2026-11-03T10:00:00Z', 'expiresAt': '2026-11-10T10:00:00Z', 'expired': false},
        {'id': 'i2', 'email': 'd@x.pt', 'createdAt': '2026-11-03T10:00:00Z', 'expiresAt': '2026-11-10T10:00:00Z', 'expired': true},
      ],
    });
    expect(data.members.first.isMe, isTrue);
    expect(data.invitations.last.expired, isTrue);
    expect(data.canInvite, isTrue, reason: '2 ativos + 1 pendente válido = 3; o expirado não conta');
    final full = FamilyMembers.fromJson({
      'members': [for (var i = 0; i < 4; i++) {'adultUserId': 'u$i', 'email': '$i@x.pt', 'joinedAt': '2026-11-01T10:00:00Z'}],
      'invitations': [],
    });
    expect(full.canInvite, isFalse);
  });

  test('InvitationPreview: estados', () {
    expect(InvitationPreview.fromJson({'status': 'pending', 'email': 'a@x.pt', 'invitedBy': 'b@x.pt'}).pending, isTrue);
    expect(InvitationPreview.fromJson({'status': 'expired', 'email': 'a@x.pt'}).pending, isFalse);
    expect(InvitationPreview.invalid.pending, isFalse);
    expect(InvitationPreview.fromJson({'status': 'pending', 'email': 'a@x.pt', 'accountExists': false}).accountExists, isFalse);
    expect(InvitationPreview.fromJson({'status': 'pending', 'email': 'a@x.pt'}).accountExists, isTrue);
  });

  test('PendingInvitationStore guarda só tokens válidos do link', () async {
    SharedPreferences.setMockInitialValues({});
    await PendingInvitationStore.captureFromUrl(Uri.parse('https://app.escolaemdia.me/convite?token=abc'));
    expect(await PendingInvitationStore.read(), isNull);
    await PendingInvitationStore.captureFromUrl(Uri.parse('https://app.escolaemdia.me/convite?token=$token'));
    expect(await PendingInvitationStore.read(), token);
    await PendingInvitationStore.clear();
    expect(await PendingInvitationStore.read(), isNull);
  });

  testWidgets('Menu de conta mostra o e-mail da sessão', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AreaTheme(palette: AreaPalette.parent, child: ParentShell(
      tab: ParentTab.family, onTabChanged: (_) {}, onLock: () {}, onSignOut: () {},
      accountEmail: 'pai@example.pt',
      dashboard: const SizedBox(), worksheets: const SizedBox(), family: const SizedBox(),
    ))));
    await tester.tap(find.byTooltip('Conta e definições'));
    await tester.pumpAndSettle();
    expect(find.text('Sessão iniciada como'), findsOneWidget);
    expect(find.text('pai@example.pt'), findsOneWidget);
  });
}
