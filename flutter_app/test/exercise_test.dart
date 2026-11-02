import 'package:flutter_test/flutter_test.dart';
import 'package:escola_em_dia/models/exercise.dart';

Map<String, dynamic> fixture({bool written = false}) => {
  'id': 'teste',
  'title': 'Teste',
  'topic': 'Sílabas',
  'questions': [
    for (var i = 0; i < 10; i++)
      {
        'id': 'q$i',
        'type': 'multiple-choice',
        'prompt': 'Pergunta $i',
        'options': [
          {'id': 'a', 'text': 'Sim'},
          {'id': 'b', 'text': 'Não'},
        ],
        'correctAnswer': 'a',
      },
    if (written)
      {'id': 'texto', 'type': 'written', 'prompt': 'Escreve uma frase.'},
  ],
};
void main() {
  test('preserva o JSON e identifica a matéria em ficheiros antigos', () {
    final exercise = Exercise.fromJson(fixture());
    expect(exercise.subject, 'Português');
    expect(exercise.json, fixture());
  });
  test('celebra em exatamente 70% e incentiva abaixo desse limite', () {
    final exercise = Exercise.fromJson(fixture());
    final answers = {for (var i = 0; i < 7; i++) 'q$i': 'a'};
    expect(exercise.percentage(answers), 70);
    expect(exercise.celebrates(answers), true);
    answers.remove('q6');
    expect(exercise.celebrates(answers), false);
    expect(exercise.result(answers), 'wrong');
  });
  test('escrita fica para revisão e não entra na percentagem', () {
    final exercise = Exercise.fromJson(fixture(written: true));
    final answers = {for (var i = 0; i < 10; i++) 'q$i': 'a'};
    expect(exercise.percentage(answers), 100);
    expect(exercise.result(answers), 'review');
    final onlyWriting = Exercise.fromJson({
      'id': 'escrita',
      'title': 'Texto',
      'topic': 'Escrita',
      'questions': [
        {'id': 'q1', 'type': 'written', 'prompt': 'Escreve.'},
      ],
    });
    expect(onlyWriting.percentage({}), null);
    expect(onlyWriting.celebrates({}), false);
  });
  test('rejeita soluções e ids inválidos', () {
    final invalid = fixture();
    (invalid['questions'] as List).first['correctAnswer'] = 'inexistente';
    expect(() => Exercise.fromJson(invalid), throwsFormatException);
    expect(
      () => Exercise.fromJson({...fixture(), 'id': '../fora'}),
      throwsFormatException,
    );
  });
}
