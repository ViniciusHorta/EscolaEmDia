import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/attempts/domain/attempt_models.dart';
import 'package:escola_em_dia/features/attempts/domain/child_feedback_models.dart';
import 'package:escola_em_dia/features/attempts/presentation/widgets/child_feedback_card.dart';
import 'package:escola_em_dia/features/attempts/presentation/widgets/question_answer_editor.dart';
import 'package:escola_em_dia/features/reviews/domain/parent_review_models.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 360, child: child))),
      );

  const trueFalse = AttemptQuestion(id: 'tf1', type: 'true_false', prompt: 'A baleia é um mamífero.', options: []);

  /// Editor com estado local, como o controlador da ficha faz com cada resposta.
  Widget editor(List<Map<String, dynamic>> changes, {bool enabled = true, AttemptQuestion question = trueFalse}) {
    var value = <String, dynamic>{'mode': 'unanswered'};
    return host(StatefulBuilder(builder: (context, setState) => QuestionAnswerEditor(
      question: question, value: value, enabled: enabled,
      onChanged: (answer) => setState(() { changes.add(answer); value = answer; }),
    )));
  }

  bool isSelected(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label)).flagsCollection.isSelected == Tristate.isTrue;

  testWidgets('Verdadeiro ou Falso: mostra as duas opções sem seleção inicial', (tester) async {
    await tester.pumpWidget(editor([]));
    expect(find.text('Verdadeiro'), findsOneWidget);
    expect(find.text('Falso'), findsOneWidget);
    expect(isSelected(tester, 'Verdadeiro'), isFalse);
    expect(isSelected(tester, 'Falso'), isFalse);
    expect(find.text('Limpar resposta'), findsNothing);
  });

  testWidgets('Verdadeiro ou Falso: seleciona, destaca e permite alterar a escolha', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes));

    await tester.tap(find.text('Verdadeiro'));
    await tester.pumpAndSettle();
    expect(changes.last, {'mode': 'true_false', 'value': true});
    expect(isSelected(tester, 'Verdadeiro'), isTrue);
    expect(isSelected(tester, 'Falso'), isFalse);

    await tester.tap(find.text('Falso'));
    await tester.pumpAndSettle();
    expect(changes.last, {'mode': 'true_false', 'value': false});
    expect(isSelected(tester, 'Verdadeiro'), isFalse, reason: 'só uma opção pode estar selecionada');
    expect(isSelected(tester, 'Falso'), isTrue);
  });

  testWidgets('Verdadeiro ou Falso: limpar deixa a pergunta sem resposta', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes));
    await tester.tap(find.text('Falso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar resposta'));
    await tester.pumpAndSettle();
    expect(changes.last, {'mode': 'unanswered'});
    expect(isSelected(tester, 'Falso'), isFalse);
  });

  testWidgets('Verdadeiro ou Falso: ficha entregue não permite alterar', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes, enabled: false));
    await tester.tap(find.text('Verdadeiro'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('Escolha múltipla mantém o formato de resposta', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes, question: const AttemptQuestion(id: 'mc', type: 'multiple-choice',
      prompt: 'Qual é um mamífero?', options: [AttemptOption('a', 'Gato'), AttemptOption('b', 'Peixe')])));
    await tester.tap(find.text('Gato'));
    await tester.pumpAndSettle();
    expect(changes.last, {'mode': 'multiple-choice', 'selectedOptionId': 'a'});
    expect(find.text('Verdadeiro'), findsNothing);
  });

  ChildFeedbackQuestion feedback(String outcome, {String? selected}) => ChildFeedbackQuestion.fromJson({
    'id': 'tf1', 'number': 3, 'type': 'true_false', 'prompt': 'Os peixes têm penas.',
    'answerType': selected == null ? 'unanswered' : 'true_false', 'answerText': '', 'outcome': outcome,
    'explanation': '', 'selectedOptionText': selected, 'correctOptionText': 'Falso',
  });

  testWidgets('Correção da criança: mostra a escolha e a resposta certa quando errou', (tester) async {
    await tester.pumpWidget(host(ChildFeedbackCard(question: feedback('incorrect', selected: 'Verdadeiro'))));
    expect(find.text('Incorreta'), findsOneWidget);
    expect(find.text('Verdadeiro'), findsOneWidget);
    expect(find.text('Resposta correta'), findsOneWidget);
    expect(find.text('Falso'), findsOneWidget);
  });

  testWidgets('Correção da criança: sem seleção conta como não respondida', (tester) async {
    await tester.pumpWidget(host(ChildFeedbackCard(question: feedback('unanswered'))));
    expect(find.text('Sem resposta'), findsOneWidget);
    expect(find.text('Esta pergunta ficou sem resposta.'), findsOneWidget);
  });

  test('Revisão parental: Verdadeiro ou Falso é corrigida automaticamente', () {
    ParentReviewQuestion question(String answerType, String? selected) => ParentReviewQuestion.fromJson({
      'id': 'tf1', 'type': 'true_false', 'prompt': 'A baleia é um mamífero.', 'answerType': answerType,
      'reviewable': false, 'explanation': '', 'selectedOptionId': selected, 'correctOptionId': 'true',
      'options': [{'id': 'true', 'text': 'Verdadeiro'}, {'id': 'false', 'text': 'Falso'}],
    });
    final right = question('true_false', 'true');
    expect(right.automatic, isTrue);
    expect(right.answeredAutomatic, isTrue);
    expect(right.optionText(right.selectedOptionId), 'Verdadeiro');
    expect(right.selectedOptionId == right.correctOptionId, isTrue);
    final wrong = question('true_false', 'false');
    expect(wrong.selectedOptionId == wrong.correctOptionId, isFalse);
    final blank = question('unanswered', null);
    expect(blank.answeredAutomatic, isFalse);
    expect(blank.optionText(blank.selectedOptionId), 'Sem resposta');
  });
}
