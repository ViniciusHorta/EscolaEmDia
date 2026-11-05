class SubmissionSummary {
  const SubmissionSummary({required this.attemptId,required this.childId,required this.title,required this.subjectName,
    required this.status,required this.submittedAt,required this.questionCount,required this.choiceTotal,
    required this.choiceCorrect,required this.writtenAnswered,required this.pendingReview,required this.unansweredTotal,
    this.attemptNumber=1,this.writtenCorrect=0,this.writtenPartial=0,this.writtenIncorrect=0});
  final String attemptId,childId,title,subjectName,status;
  final DateTime submittedAt;
  final int attemptNumber;
  final int writtenCorrect,writtenPartial,writtenIncorrect;
  final int questionCount,choiceTotal,choiceCorrect,writtenAnswered,pendingReview,unansweredTotal;
  factory SubmissionSummary.fromJson(Map value)=>SubmissionSummary(
    attemptNumber:value['attemptNumber'] as int? ?? 1,
    attemptId:value['attemptId'] as String,childId:value['childId'] as String,title:value['title'] as String,
    subjectName:value['subjectName'] as String,status:value['status'] as String,
    submittedAt:DateTime.parse(value['submittedAt'] as String),questionCount:value['questionCount'] as int,
    choiceTotal:value['choiceTotal'] as int,choiceCorrect:value['choiceCorrect'] as int,
    writtenAnswered:value['writtenAnswered'] as int,pendingReview:value['pendingReview'] as int,
    unansweredTotal:value['unansweredTotal'] as int,
    writtenCorrect:value['writtenCorrect'] as int? ?? 0,writtenPartial:value['writtenPartial'] as int? ?? 0,
    writtenIncorrect:value['writtenIncorrect'] as int? ?? 0);
}
