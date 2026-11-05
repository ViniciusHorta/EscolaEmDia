import '../../attempts/domain/submission_summary.dart';
import '../../family/domain/family_models.dart';

class ProgressTotals {
  const ProgressTotals({required this.assignedTotal, required this.toStart, required this.inProgress,
    required this.delivered, required this.completed, required this.pendingAttempts, required this.pendingAnswers});
  final int assignedTotal, toStart, inProgress, delivered, completed, pendingAttempts, pendingAnswers;
  factory ProgressTotals.fromJson(Map value) => ProgressTotals(
    assignedTotal: value['assignedTotal'] as int, toStart: value['toStart'] as int,
    inProgress: value['inProgress'] as int, delivered: value['delivered'] as int,
    completed: value['completed'] as int, pendingAttempts: value['pendingAttempts'] as int,
    pendingAnswers: value['pendingAnswers'] as int,
  );
}
class SubjectProgress {
  const SubjectProgress({required this.id, required this.name, required this.totals,
    required this.choiceTotal, required this.choiceCorrect, required this.writtenAnswered,
    required this.writtenCorrect, required this.writtenPartial, required this.writtenIncorrect, required this.unansweredTotal});
  final String id, name;
  final ProgressTotals totals;
  final int choiceTotal, choiceCorrect, writtenAnswered, writtenCorrect, writtenPartial, writtenIncorrect, unansweredTotal;
  factory SubjectProgress.fromJson(Map value) => SubjectProgress(
    id: value['subjectId'] as String, name: value['subjectName'] as String, totals: ProgressTotals.fromJson(value),
    choiceTotal: value['choiceTotal'] as int, choiceCorrect: value['choiceCorrect'] as int,
    writtenAnswered: value['writtenAnswered'] as int, writtenCorrect: value['writtenCorrect'] as int,
    writtenPartial: value['writtenPartial'] as int, writtenIncorrect: value['writtenIncorrect'] as int,
    unansweredTotal: value['unansweredTotal'] as int,
  );
}
class ChildProgress {
  const ChildProgress({required this.child, required this.overview, required this.subjects});
  final ChildProfile child;
  final ProgressTotals overview;
  final List<SubjectProgress> subjects;
  factory ChildProgress.fromJson(Map value) => ChildProgress(
    child: ChildProfile.fromJson(value['child'] as Map), overview: ProgressTotals.fromJson(value['overview'] as Map),
    subjects: (value['subjects'] as List).cast<Map>().map(SubjectProgress.fromJson).toList(),
  );
}
class AttemptHistoryEntry {
  const AttemptHistoryEntry({required this.id, required this.childId, required this.title,
    required this.subjectId, required this.subjectName, required this.status, required this.startedAt,
    required this.assignmentActive, required this.questionCount, this.submittedAt, this.summary, this.attemptNumber=1});
  final String id, childId, title, subjectId, subjectName, status;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final bool assignmentActive;
  final int questionCount, attemptNumber;
  final SubmissionSummary? summary;
  factory AttemptHistoryEntry.fromJson(Map value) => AttemptHistoryEntry(
    attemptNumber: value['attemptNumber'] as int? ?? 1,
    id: value['attemptId'] as String, childId: value['childId'] as String, title: value['title'] as String,
    subjectId: value['subjectId'] as String, subjectName: value['subjectName'] as String, status: value['status'] as String,
    startedAt: DateTime.parse(value['startedAt'] as String),
    submittedAt: value['submittedAt'] == null ? null : DateTime.parse(value['submittedAt'] as String),
    assignmentActive: value['assignmentActive'] as bool, questionCount: value['questionCount'] as int,
    summary: value['summary'] is Map ? SubmissionSummary.fromJson(value['summary'] as Map) : null,
  );
}
class AttemptHistoryPage {
  const AttemptHistoryPage(this.items, this.nextCursor);
  final List<AttemptHistoryEntry> items;
  final String? nextCursor;
  factory AttemptHistoryPage.fromJson(Map value) => AttemptHistoryPage(
    (value['items'] as List).cast<Map>().map(AttemptHistoryEntry.fromJson).toList(), value['nextCursor'] as String?,
  );
}
String historyStatusLabel(String status) => switch (status) {
  'in_progress' => 'Em curso', 'submitted' => 'Entregue', 'pending_review' => 'Aguarda revisão',
  'completed' => 'Concluída', 'abandoned' => 'Interrompida', _ => 'Estado desconhecido',
};
