import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:escola_em_dia/models/exercise.dart';
import 'package:escola_em_dia/services/exercise_api.dart';
import 'package:escola_em_dia/services/school_state.dart';

Exercise example(String id, String subject) => Exercise.fromJson({
  'id': id,
  'title': id,
  'subject': subject,
  'topic': 'Revisão',
  'questions': [
    {
      'id': 'q1',
      'type': 'multiple-choice',
      'prompt': 'Escolhe a correta.',
      'options': [
        {'id': 'a', 'text': 'Sim'},
        {'id': 'b', 'text': 'Não'},
      ],
      'correctAnswer': 'a',
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sessões independentes, revalidação sem duplicados e recuperação do progresso', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final school = SchoolState(api: ExerciseApi(), preferences: preferences);
    final portuguese = example('pt', 'Português');
    final english = example('en', 'Inglês');
    school.exercises = [portuguese, english];
    school.answer(portuguese, 'q1', 'a');
    school.startSession('Português');
    expect(school.attempt(portuguese).answers, isEmpty);
    school.answer(portuguese, 'q1', 'b');
    school.validate(portuguese);
    expect(school.counts('Português')['wrong'], 1);
    school.answer(portuguese, 'q1', 'a');
    school.validate(portuguese);
    expect(school.counts('Português'), {'correct': 1, 'wrong': 0, 'review': 0});
    school.startSession('Inglês');
    school.validate(english);
    expect(school.counts('Inglês')['wrong'], 1);
    expect(school.counts('Português')['correct'], 1);
    school.finishSession('Português');
    expect(school.attempt(portuguese).answers['q1'], 'a');
    await school.persist();
    final restored = SchoolState(api: ExerciseApi(), preferences: preferences)
      ..exercises = [portuguese, english];
    expect(restored.counts('Português')['correct'], 1);
    expect(restored.sessions['Inglês']!.active, true);
    restored.startSession('Português');
    expect(restored.counts('Português')['correct'], 0);
    expect(restored.counts('Inglês')['wrong'], 1);
    await restored.persist();
    school.dispose();
    restored.dispose();
  });
}
