class AnswerOption {
  const AnswerOption(this.id, this.text);
  final String id;
  final String text;
}

class Question {
  const Question({
    required this.id,
    required this.prompt,
    required this.type,
    this.options = const [],
    this.correctAnswer,
    this.explanation = '',
  });
  final String id;
  final String prompt;
  final String type;
  final List<AnswerOption> options;
  final String? correctAnswer;
  final String explanation;
  bool get isChoice => type == 'multiple-choice';
}

class Exercise {
  Exercise._(this.json, this.questions);
  final Map<String, dynamic> json;
  final List<Question> questions;
  String get id => json['id'] as String;
  String get title => json['title'] as String;
  String get topic => json['topic'] as String;
  String get instructions =>
      json['instructions'] as String? ?? 'Lê com atenção e responde.';
  String get text => json['text'] as String? ?? '';
  String get audioText => json['audioText'] as String? ?? '';
  String get subject {
    final explicit = (json['subject'] as String? ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    if (topic == 'Estudo do Meio') return topic;
    const portuguese = {
      'Compreensão oral',
      'Compreensão escrita',
      'Dicionário',
      'Sílabas',
      'Sílaba tónica',
      'Onomatopeias',
      'Formação de palavras',
      'Família de palavras',
      'Expressão escrita',
    };
    return portuguese.contains(topic) ? 'Português' : 'Outras matérias';
  }

  List<Question> get choices => questions.where((q) => q.isChoice).toList();
  bool get hasWriting => questions.any((q) => !q.isChoice);

  factory Exercise.fromJson(dynamic value) {
    Never fail(String message) => throw FormatException(message);
    bool text(dynamic value) => value is String && value.trim().isNotEmpty;
    if (value is! Map<String, dynamic>)
      fail('O exercício deve ser um objeto JSON.');
    final data = Map<String, dynamic>.from(value);
    if (data['id'] is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{0,79}$').hasMatch(data['id'] as String)) {
      fail('O id deve ter até 80 letras minúsculas, números ou hífens.');
    }
    if (!text(data['title']) || !text(data['topic']))
      fail('Preenche title e topic.');
    for (final key in ['subject', 'instructions', 'text', 'audioText']) {
      if (data.containsKey(key) && data[key] is! String)
        fail('$key deve ser texto.');
    }
    final raw = data['questions'];
    if (raw is! List || raw.isEmpty || raw.length > 50)
      fail('Inclui entre 1 e 50 perguntas.');
    final questions = <Question>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map || !text(item['id']) || !ids.add(item['id'] as String))
        fail('Cada pergunta precisa de um id único.');
      if (!text(item['prompt'])) fail('Cada pergunta precisa de prompt.');
      if (!['multiple-choice', 'written'].contains(item['type']))
        fail('Usa multiple-choice ou written.');
      if (item.containsKey('explanation') && item['explanation'] is! String)
        fail('explanation deve ser texto.');
      final options = <AnswerOption>[];
      if (item['type'] == 'multiple-choice') {
        final rawOptions = item['options'];
        if (rawOptions is! List ||
            rawOptions.length < 2 ||
            rawOptions.length > 8)
          fail('Inclui entre 2 e 8 opções.');
        final optionIds = <String>{};
        for (final option in rawOptions) {
          if (option is! Map ||
              !text(option['id']) ||
              !text(option['text']) ||
              !optionIds.add(option['id'] as String))
            fail('As opções precisam de id único e text.');
          options.add(
            AnswerOption(option['id'] as String, option['text'] as String),
          );
        }
        if (!optionIds.contains(item['correctAnswer']))
          fail('correctAnswer deve ser o id de uma opção.');
      }
      questions.add(
        Question(
          id: item['id'] as String,
          prompt: item['prompt'] as String,
          type: item['type'] as String,
          options: options,
          correctAnswer: item['type'] == 'multiple-choice'
              ? item['correctAnswer'] as String
              : null,
          explanation: item['explanation'] as String? ?? '',
        ),
      );
    }
    return Exercise._(data, questions);
  }

  int correctCount(Map<String, String> answers) =>
      choices.where((q) => answers[q.id] == q.correctAnswer).length;
  int? percentage(Map<String, String> answers) =>
      choices.isEmpty ? null : correctCount(answers) * 100 ~/ choices.length;
  bool celebrates(Map<String, String> answers) =>
      choices.isNotEmpty && correctCount(answers) * 100 >= choices.length * 70;
  String result(Map<String, String> answers) {
    if (choices.any((q) => answers[q.id] != q.correctAnswer)) return 'wrong';
    return hasWriting ? 'review' : 'correct';
  }
}
