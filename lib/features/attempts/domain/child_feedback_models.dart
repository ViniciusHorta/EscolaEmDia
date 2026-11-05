import 'submission_summary.dart';

class ChildFeedbackQuestion {
  const ChildFeedbackQuestion({required this.id, required this.number, required this.type,
    required this.prompt, required this.answerType, required this.answerText, required this.outcome,
    required this.explanation, this.selectedOptionText, this.correctOptionText});
  final String id, type, prompt, answerType, answerText, outcome, explanation;
  final String? selectedOptionText, correctOptionText;
  final int number;
  bool get needsPractice => outcome != 'correct';
  factory ChildFeedbackQuestion.fromJson(Map value) {
    final outcome = value['outcome'] as String;
    if (!['correct', 'partially_correct', 'incorrect', 'unanswered', 'pending_review'].contains(outcome)) {
      throw const FormatException('Classificação desconhecida');
    }
    return ChildFeedbackQuestion(
      id: value['id'] as String, number: value['number'] as int, type: value['type'] as String,
      prompt: value['prompt'] as String, answerType: value['answerType'] as String,
      answerText: value['answerText'] as String, outcome: outcome, explanation: value['explanation'] as String,
      selectedOptionText: value['selectedOptionText'] as String?, correctOptionText: value['correctOptionText'] as String?,
    );
  }
}
class ChildAttemptFeedback {
  const ChildAttemptFeedback({required this.summary, required this.questions, required this.instructions,
    required this.text, required this.audioText});
  final SubmissionSummary summary;
  final List<ChildFeedbackQuestion> questions;
  final String instructions, text, audioText;
  factory ChildAttemptFeedback.fromJson(Map value) => ChildAttemptFeedback(
    summary: SubmissionSummary.fromJson(value['summary'] as Map),
    questions: (value['questions'] as List).cast<Map>().map(ChildFeedbackQuestion.fromJson).toList(),
    instructions: value['instructions'] as String, text: value['text'] as String, audioText: value['audioText'] as String,
  );
}
