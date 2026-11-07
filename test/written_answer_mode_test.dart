import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/core/theme/app_theme.dart';
import 'package:escola_em_dia/features/attempts/domain/attempt_models.dart';
import 'package:escola_em_dia/features/attempts/presentation/widgets/question_answer_editor.dart';

void main() {
  const written = AttemptQuestion(id: 'w1', type: 'written', prompt: 'Explica o teu raciocínio.', options: []);

  Widget editor(List<Map<String, dynamic>> changes, String mode) {
    var value = <String, dynamic>{'mode': 'unanswered'};
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 360, child: StatefulBuilder(
        builder: (context, setState) => QuestionAnswerEditor(
          question: written, value: value, enabled: true, writtenAnswerMode: mode,
          onChanged: (answer) => setState(() { changes.add(answer); value = answer; }),
        ),
      )))),
    );
  }

  testWidgets('Modo escolhido pelo responsável «na app»: só mostra a caixa de texto', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes, 'typed'));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('No caderno'), findsNothing);
    expect(find.text('No teu caderno'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Somei as duas partes.');
    expect(changes.last, {'mode': 'typed', 'text': 'Somei as duas partes.'});
  });

  testWidgets('Modo escolhido pelo responsável «no caderno»: só permite assinalar que terminou', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(editor(changes, 'paper'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Escrever aqui'), findsNothing);
    await tester.tap(find.text('Já resolvi o desafio no meu caderno'));
    await tester.pumpAndSettle();
    expect(changes.last, {'mode': 'paper'});
  });

  test('Snapshot lê o modo definido na atribuição (por omissão, na app)', () {
    Map<String, dynamic> payload([String? mode]) => {
      'id': 'a', 'childId': 'c', 'assignmentId': 's', 'status': 'in_progress', 'title': 't', 'subjectName': 'Português',
      'writable': true, 'questions': [], 'answers': [], if (mode != null) 'writtenAnswerMode': mode,
    };
    expect(AttemptSnapshot.fromJson(payload('paper')).writtenAnswerMode, 'paper');
    expect(AttemptSnapshot.fromJson(payload('typed')).writtenAnswerMode, 'typed');
    expect(AttemptSnapshot.fromJson(payload()).writtenAnswerMode, 'typed');
  });
}
