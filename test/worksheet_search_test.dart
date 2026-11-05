import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/core/utils/search_text.dart';
import 'package:escola_em_dia/features/family/domain/family_models.dart';
import 'package:escola_em_dia/features/worksheets/data/worksheet_service.dart';
import 'package:escola_em_dia/features/worksheets/domain/worksheet_models.dart';
import 'package:escola_em_dia/features/worksheets/presentation/prepare_worksheet_page.dart';

WorksheetSummary sheet(String id, String title, List<String> topics) => WorksheetSummary.fromJson({
  'id': id, 'versionId': 'v$id', 'title': title, 'subjectName': 'Matemática', 'schoolYear': 3,
  'questionCount': 6, 'choiceCount': 4, 'writtenCount': 2, 'topicNames': topics});

const fractions = SchoolTopic('t1', 'Frações e Partes');
const tables = SchoolTopic('t2', 'Multiplicação & Tabuadas');
final catalogue = [
  sheet('w1', 'Frações e Multiplicação', [fractions.name, tables.name]),
  sheet('w2', 'Partes iguais', [fractions.name]),
  sheet('w3', 'Pizzas e metades', [fractions.name]),
  sheet('w4', 'Tabuada do 7', [tables.name]),
];

/// Catálogo em memória com a mesma regra do servidor: sem temas devolve tudo;
/// com temas devolve as fichas cujo conjunto de temas é exatamente o selecionado.
class FakeWorksheets extends WorksheetService {
  FakeWorksheets() : super(SupabaseClient('http://localhost:1', 'k',
    authOptions: const AuthClientOptions(autoRefreshToken: false)), parentToken: _token, onParentLocked: _none);
  static String? _token() => 'x';
  static void _none() {}
  final opened = <String>[];
  @override
  Future<List<SchoolSubject>> subjects() async => const [SchoolSubject('s1', 'Matemática')];
  @override
  Future<List<SchoolTopic>> topics(String subjectId, int year) async => const [fractions, tables];
  @override
  Future<List<WorksheetSummary>> proposals(String subjectId, int year, Set<String> topicIds) async {
    if (topicIds.isEmpty) return catalogue;
    final names = {for (final t in [fractions, tables]) if (topicIds.contains(t.id)) t.name};
    return catalogue.where((w) => w.topicNames.toSet().containsAll(names) && names.containsAll(w.topicNames)).toList();
  }
  @override
  Future<Map> detail(WorksheetSummary worksheet) async { opened.add(worksheet.title); return {'content': {'questions': []}}; }
}

void main() {
  test('pesquisa ignora maiúsculas, acentos e ordem das palavras', () {
    expect(normalizeSearch('  Frações   e PARTES '), 'fracoes e partes');
    expect(matchesSearch('Frações e Partes', 'fracoes'), isTrue);
    expect(matchesSearch('Frações e Partes', 'partes FRAÇÕES'), isTrue);
    expect(matchesSearch('Frações e Partes', 'tabuada'), isFalse);
    expect(matchesSearch('Qualquer texto', '   '), isTrue);
  });

  Future<FakeWorksheets> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final service = FakeWorksheets();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: PrepareWorksheetPage(
      children: const [ChildProfile(id: 'c1', familyId: 'f', displayName: 'Martim', schoolYear: 3, avatarId: 'fox')],
      service: service, onClose: () {}, onViewChild: (_) async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matemática'));
    await tester.pumpAndSettle();
    return service;
  }

  Finder searchBox(String hint) => find.widgetWithText(TextField, hint);

  testWidgets('pesquisa de temas encontra pelo nome do tema', (tester) async {
    await open(tester);
    await tester.enterText(searchBox('Pesquisar tema ou nome de ficha'), 'tabuadas');
    await tester.pump();
    expect(find.text(tables.name), findsOneWidget);
    expect(find.text(fractions.name), findsNothing);
  });

  testWidgets('pesquisa de temas encontra pelo nome das fichas e mostra a ficha', (tester) async {
    await open(tester);
    await tester.enterText(searchBox('Pesquisar tema ou nome de ficha'), 'pizza');
    await tester.pump();
    expect(find.text(fractions.name), findsOneWidget);
    expect(find.text(tables.name), findsNothing);
    expect(find.text('Ficha: «Pizzas e metades»'), findsOneWidget);

    await tester.enterText(searchBox('Pesquisar tema ou nome de ficha'), 'dinossauros');
    await tester.pump();
    expect(find.text('Nenhum tema ou ficha encontrado para «dinossauros».'), findsOneWidget);
  });

  testWidgets('temas selecionados continuam visíveis durante a pesquisa', (tester) async {
    await open(tester);
    await tester.tap(find.text(tables.name));
    await tester.pump();
    await tester.enterText(searchBox('Pesquisar tema ou nome de ficha'), 'pizza');
    await tester.pump();
    expect(find.text(tables.name), findsOneWidget);
  });

  testWidgets('o termo pesquisado passa para a seleção da ficha', (tester) async {
    final service = await open(tester);
    await tester.enterText(searchBox('Pesquisar tema ou nome de ficha'), 'pizza');
    await tester.pump();
    await tester.tap(find.text(fractions.name));
    await tester.pump();
    await tester.ensureVisible(find.text('Ver Proposta de Ficha'));
    await tester.tap(find.text('Ver Proposta de Ficha'));
    await tester.pumpAndSettle();

    // A ficha proposta à partida é a que corresponde ao termo, e não a primeira do catálogo.
    expect(service.opened, ['Pizzas e metades']);
    final search = tester.widget<TextField>(searchBox('Pesquisar ficha por nome ou tema'));
    expect(search.controller!.text, 'pizza');
    expect(find.text('Partes iguais'), findsNothing);

    // A pesquisa de fichas filtra a lista e pode ser limpa.
    await tester.tap(find.byTooltip('Limpar pesquisa'));
    await tester.pump();
    expect(find.text('Partes iguais'), findsOneWidget);
    await tester.enterText(searchBox('Pesquisar ficha por nome ou tema'), 'xyz');
    await tester.pump();
    expect(find.text('Nenhuma ficha encontrada para «xyz».'), findsOneWidget);
  });
}
