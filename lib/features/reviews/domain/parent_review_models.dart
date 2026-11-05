import '../../attempts/domain/submission_summary.dart';
import '../../family/domain/family_models.dart';

enum ReviewClassification {
  correct('correct', 'Correta'),
  partiallyCorrect('partially_correct', 'Parcialmente correta'),
  incorrect('incorrect', 'Incorreta');

  const ReviewClassification(this.value, this.label);
  final String value, label;
  static ReviewClassification parse(String value) => values.firstWhere((item) => item.value == value);
}

class AnswerReview {
  const AnswerReview({required this.id, required this.classification, required this.revision, required this.reviewedAt});
  final String id;
  final ReviewClassification classification;
  final int revision;
  final DateTime reviewedAt;
  factory AnswerReview.fromJson(Map value) => AnswerReview(
    id: value['answerReviewId'] as String,
    classification: ReviewClassification.parse(value['classification'] as String),
    revision: value['revision'] as int,
    reviewedAt: DateTime.parse(value['reviewedAt'] as String),
  );
}

class ReviewOption {
  const ReviewOption(this.id, this.text);
  final String id, text;
}

class ParentReviewQuestion {
  const ParentReviewQuestion({required this.id, required this.type, required this.prompt,
    required this.answerType, required this.reviewable, required this.options,
    required this.explanation, this.answerId, this.text, this.selectedOptionId, this.correctOptionId, this.review});
  final String id, type, prompt, answerType, explanation;
  final String? answerId, text, selectedOptionId, correctOptionId;
  final bool reviewable;
  final List<ReviewOption> options;
  final AnswerReview? review;
  factory ParentReviewQuestion.fromJson(Map value) => ParentReviewQuestion(
    id: value['id'] as String, type: value['type'] as String, prompt: value['prompt'] as String,
    answerType: value['answerType'] as String, reviewable: value['reviewable'] as bool,
    answerId: value['answerId'] as String?, text: value['text'] as String?,
    selectedOptionId: value['selectedOptionId'] as String?, correctOptionId: value['correctOptionId'] as String?,
    explanation: value['explanation'] as String? ?? '',
    options: (value['options'] as List).map((item) => ReviewOption(item['id'] as String, item['text'] as String)).toList(),
    review: value['review'] is Map ? AnswerReview.fromJson(value['review'] as Map) : null,
  );
  String optionText(String? id) {
    for (final option in options) { if (option.id == id) return option.text; }
    return 'Sem resposta';
  }
}

class ParentAttemptReview {
  const ParentAttemptReview({required this.summary, required this.child, required this.questions,
    required this.instructions, required this.text, required this.audioText});
  final SubmissionSummary summary;
  final ChildProfile child;
  final List<ParentReviewQuestion> questions;
  final String instructions, text, audioText;
  factory ParentAttemptReview.fromJson(Map value) => ParentAttemptReview(
    summary: SubmissionSummary.fromJson(value), child: ChildProfile.fromJson(value['child'] as Map),
    questions: (value['questions'] as List).cast<Map>().map(ParentReviewQuestion.fromJson).toList(),
    instructions: value['instructions'] as String? ?? '', text: value['text'] as String? ?? '',
    audioText: value['audioText'] as String? ?? '',
  );

}

class ReviewChange {
  const ReviewChange({required this.answerId, required this.classification, required this.baseRevision, required this.operationId});
  final String answerId, operationId;
  final ReviewClassification classification;
  final int baseRevision;
  Map<String, dynamic> toJson() => {'classification': classification.value, 'baseRevision': baseRevision, 'operationId': operationId};
}
