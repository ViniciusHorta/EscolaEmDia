import 'package:escola_em_dia/features/attempts/domain/attempt_models.dart';
import 'package:escola_em_dia/shared/widgets/question_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê a imagem da questão e monta o URL público do bucket', () {
    final img = QuestionImage.tryParse({'path': 'pasta/a b.webp', 'alt': ' Três maçãs '})!;
    expect(img.alt, 'Três maçãs');
    expect(img.url, endsWith('/storage/v1/object/public/question-images/pasta/a%20b.webp'));
  });

  test('ignora imagem ausente ou mal formada', () {
    expect(QuestionImage.tryParse(null), isNull);
    expect(QuestionImage.tryParse('abc.png'), isNull);
    expect(QuestionImage.tryParse({'path': ''}), isNull);
    expect(QuestionImage.tryParse({'alt': 'x'}), isNull);
  });

  test('questão sem imagem continua igual; com imagem expõe-na', () {
    final plain = AttemptQuestion.fromJson({'id': 'q1', 'type': 'written', 'prompt': 'P'});
    expect(plain.image, isNull);
    final withImg = AttemptQuestion.fromJson({'id': 'q1', 'type': 'written', 'prompt': 'P', 'image': {'path': 'x.png'}});
    expect(withImg.image?.path, 'x.png');
    expect(withImg.image?.alt, '');
  });
}
