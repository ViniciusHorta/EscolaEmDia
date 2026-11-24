import 'package:escola_em_dia/features/progress/domain/learning_models.dart';
import 'package:escola_em_dia/features/progress/presentation/widgets/learning_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> axis(String id, String name, {int attempts = 1, int exercises = 0, int correct = 0,
    int partial = 0, int incorrect = 0, int pending = 0, Map<String, int>? previous}) =>
  {'id': id, 'name': name, 'attempts': attempts, 'exercises': exercises, 'correct': correct, 'partial': partial,
    'incorrect': incorrect, 'pending': pending, 'previous': previous};

LearningOverview overview(List<Map<String, dynamic>> axes, {String plan = 'free', int completed = 12}) =>
  LearningOverview.fromJson({'child': {'id': 'c1', 'displayName': 'Martim', 'schoolYear': 4}, 'plan': plan,
    'period': '30d', 'completedAttempts': completed, 'subject': null, 'axes': axes});

List<int> rounded(List<double> values) => [for (final v in values) v.round()];

void main() {
  group('Índice de prática (PRD §9)', () {
    test('exemplo do PRD: 44, 52, 40, 32', () {
      final p = practiceIndices([44, 52, 40, 32]);
      expect(p[0], closeTo(83.81, 0.01));
      expect(p[1], closeTo(99.05, 0.01));
      expect(p[2], closeTo(76.19, 0.01));
      expect(p[3], closeTo(60.95, 0.01));
    });
    test('comportamentos especiais (§9.5)', () {
      expect(rounded(practiceIndices([10, 10, 10, 10])), [80, 80, 80, 80]);
      expect(rounded(practiceIndices([20, 10, 10, 0])), [100, 50, 50, 0]);
      expect(rounded(practiceIndices([10, 0, 0, 0])), [100, 0, 0, 0]);
      expect(practiceIndices([0, 0, 0, 0]), [0, 0, 0, 0]);
    });
    test('nenhum índice passa de 100', () {
      expect(practiceIndices([1000, 1, 1]).every((v) => v <= 100), isTrue);
    });
  });

  group('Desempenho (PRD §10 e §13)', () {
    test('exemplo do PRD: 14 certas, 4 parciais, 2 incorretas → 80%', () {
      const counts = AnswerCounts(correct: 14, partial: 4, incorrect: 2);
      expect(counts.performance, 80);
      expect(counts.state, PerformanceState.available);
    });
    test('sem perguntas avaliadas não é 0%', () {
      expect(const AnswerCounts().performance, isNull);
      expect(const AnswerCounts().state, PerformanceState.none);
      expect(percentLabel(null), '—');
    });
    test('todas incorretas é 0% real; 1–19 são dados iniciais', () {
      const counts = AnswerCounts(incorrect: 5);
      expect(counts.performance, 0);
      expect(counts.state, PerformanceState.initial);
    });
  });

  group('Evolução (PRD §15)', () {
    test('compara quando os dois períodos têm 20+ avaliadas', () {
      final o = overview([axis('m', 'Matemática', exercises: 30, correct: 41, incorrect: 9,
        previous: {'correct': 14, 'partial': 0, 'incorrect': 6})], plan: 'premium');
      expect(o.axes.single.evolution, 12); // 82% − 70%
      expect(evolutionLabel(12), '+12 p.p.');
      expect(evolutionLabel(-7), '-7 p.p.');
    });
    test('sem evolução com dados insuficientes ou sem período anterior', () {
      final few = overview([axis('m', 'M', exercises: 5, correct: 5, previous: {'correct': 20, 'partial': 0, 'incorrect': 0})]);
      expect(few.axes.single.evolution, isNull);
      expect(overview([axis('m', 'M', exercises: 30, correct: 30)]).axes.single.evolution, isNull);
    });
  });

  group('Sugestões (PRD §16)', () {
    LearningAxis make(String id, {required double practice, double? perf, int evaluated = 30, int exercises = 10}) {
      final correct = perf == null ? 0 : (perf / 100 * evaluated).round();
      return LearningAxis(id: id, name: id, attempts: 1, exercises: exercises, pending: 0, practice: practice,
        answers: perf == null ? const AnswerCounts() : AnswerCounts(correct: correct, incorrect: evaluated - correct));
    }
    test('matriz prática × desempenho', () {
      expect(suggestionFor(make('a', practice: 90, perf: 40)), SuggestionKind.review);
      expect(suggestionFor(make('a', practice: 30, perf: 40)), SuggestionKind.reinforce);
      expect(suggestionFor(make('a', practice: 60, perf: 40)), SuggestionKind.reinforce); // HP06
      expect(suggestionFor(make('a', practice: 90, perf: 70)), SuggestionKind.consolidate);
      expect(suggestionFor(make('a', practice: 30, perf: 90)), SuggestionKind.maintain);
      expect(suggestionFor(make('a', practice: 90, perf: 90)), isNull);
    });
    test('poucos dados não sinalizam dificuldade; sem prática não sugere nada', () {
      expect(suggestionFor(make('a', practice: 90, perf: 10, evaluated: 10)), SuggestionKind.moreData);
      expect(suggestionFor(make('a', practice: 0, exercises: 0)), isNull);
    });
    test('máximo de 3, por prioridade e depois menor desempenho', () {
      final list = studySuggestions([
        make('manter', practice: 30, perf: 90), make('consolidar', practice: 90, perf: 70),
        make('rever-b', practice: 90, perf: 50), make('rever-a', practice: 95, perf: 30),
        make('dados', practice: 50, perf: 50, evaluated: 5),
      ]);
      expect([for (final s in list) s.axis.id], ['rever-a', 'rever-b', 'consolidar']);
      expect(studySuggestions([make('x', practice: 90, perf: 95)]), isEmpty);
    });
  });

  test('estado global do radar (§13.2)', () {
    expect(overview([], completed: 0).radarState, RadarState.empty);
    expect(overview([], completed: 3).radarState, RadarState.initial);
    expect(overview([], completed: 10).radarState, RadarState.normal);
  });

  group('Ecrã', () {
    final data = overview([
      axis('m', 'Matemática', exercises: 44, correct: 17, incorrect: 3),
      axis('p', 'Português', exercises: 52, correct: 10, partial: 4, incorrect: 6, pending: 2),
      axis('e', 'Estudo do Meio', exercises: 40, correct: 18, incorrect: 2),
      axis('i', 'Inglês', attempts: 0),
    ]);

    Future<void> pump(WidgetTester tester, {required LearningLoader load, VoidCallback? onUpgrade,
        LearningPrepare? onPrepare, bool premium = false}) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LearningSection(
        isPremium: premium, load: load, onUpgrade: onUpgrade, onPrepare: onPrepare)))));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra valores, «—» sem dados e aviso de revisões', (tester) async {
      await pump(tester, load: (_, __) async => data);
      expect(find.text('Matemática'), findsWidgets);
      expect(find.bySemanticsLabel('Matemática. Prática 85%. Desempenho 85%.'), findsOneWidget);
      expect(find.bySemanticsLabel('Inglês. Prática 0%. Desempenho sem dados.'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('2 respostas aguardam revisão'), findsOneWidget);
    });

    testWidgets('período Premium no plano Gratuito abre a oferta e não recarrega', (tester) async {
      var calls = 0, upgrades = 0;
      await pump(tester, load: (_, __) async { calls++; return data; }, onUpgrade: () => upgrades++);
      await tester.tap(find.text('7 dias'));
      await tester.pumpAndSettle();
      expect(upgrades, 1);
      expect(calls, 1);
    });

    testWidgets('tocar numa disciplina abre o detalhe e permite preparar atividade', (tester) async {
      String? prepared;
      await pump(tester, load: (_, __) async => data, onPrepare: ({subjectId, topicId}) => prepared = subjectId);
      final row = find.bySemanticsLabel(RegExp(r'^Português\. Prática'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Exercícios realizados'), findsOneWidget);
      expect(find.text('52'), findsOneWidget);
      await tester.ensureVisible(find.text('Preparar atividade'));
      await tester.tap(find.text('Preparar atividade'));
      await tester.pumpAndSettle();
      expect(prepared, 'p');
    });

    testWidgets('Gratuito não mostra sugestões, mas mostra o convite Premium', (tester) async {
      await pump(tester, load: (_, __) async => data, onUpgrade: () {});
      expect(find.text('Sugestões de estudo'), findsNothing);
      expect(find.textContaining('No Premium: sugestões de estudo'), findsOneWidget);
    });

    testWidgets('Premium: sugestões e exploração por tema com preparação pré-preenchida', (tester) async {
      final premium = overview(data.axes.map((a) => {'id': a.id, 'name': a.name, 'attempts': a.attempts,
        'exercises': a.exercises, 'correct': a.answers.correct, 'partial': a.answers.partial,
        'incorrect': a.answers.incorrect, 'pending': a.pending}).toList(), plan: 'premium');
      final topics = LearningOverview.fromJson({'child': {'id': 'c1', 'displayName': 'Martim', 'schoolYear': 4},
        'plan': 'premium', 'period': '30d', 'completedAttempts': 12, 'subject': {'id': 'p', 'name': 'Português'},
        'axes': [axis('t1', 'Leitura', exercises: 20, correct: 10, incorrect: 10), axis('t2', 'Gramática', exercises: 10,
          correct: 15, incorrect: 5), axis('t3', 'Escrita', exercises: 5, correct: 3, incorrect: 1)]});
      final requests = <String?>[];
      ({String? subjectId, String? topicId})? prepared;
      await pump(tester, premium: true, load: (_, subject) async { requests.add(subject); return subject == null ? premium : topics; },
        onPrepare: ({subjectId, topicId}) => prepared = (subjectId: subjectId, topicId: topicId));
      expect(find.text('Sugestões de estudo'), findsOneWidget);
      expect(find.text('Consolidar Português'), findsOneWidget); // prática 100%, desempenho 60% → intermédio
      final row = find.bySemanticsLabel(RegExp(r'^Português\. Prática'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explorar temas'));
      await tester.pumpAndSettle();
      expect(requests, [null, 'p']);
      expect(find.text('Temas de Português'), findsOneWidget);
      expect(find.text('Todas as disciplinas'), findsOneWidget);
      expect(find.text('Consolidar Gramática'), findsOneWidget);
      expect(find.text('Explorar Escrita'), findsOneWidget); // só 4 perguntas avaliadas
      final suggestion = find.text('Rever Leitura'); // prática 100%, desempenho 50%
      await tester.ensureVisible(suggestion);
      final button = find.descendant(of: find.ancestor(of: suggestion, matching: find.byType(Column)).last,
        matching: find.text('Preparar atividade'));
      await tester.ensureVisible(button.first);
      await tester.tap(button.first);
      expect(prepared, (subjectId: 'p', topicId: 't1'));
    });

    testWidgets('sem fichas no período mostra estado vazio', (tester) async {
      await pump(tester, load: (_, __) async => overview([axis('m', 'Matemática', attempts: 0)], completed: 0));
      expect(find.textContaining('Ainda não há fichas entregues'), findsOneWidget);
    });

    testWidgets('erro não mostra indicadores e permite tentar novamente', (tester) async {
      await pump(tester, load: (_, __) async => throw Exception('x'));
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('Matemática'), findsNothing);
    });
  });
}
