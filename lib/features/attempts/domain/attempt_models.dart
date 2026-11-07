class AttemptOption {
  const AttemptOption(this.id,this.text);
  final String id,text;
  factory AttemptOption.fromJson(Map value)=>AttemptOption(value['id'] as String,value['text'] as String);
}
class AttemptQuestion {
  const AttemptQuestion({required this.id,required this.type,required this.prompt,required this.options});
  final String id,type,prompt;
  final List<AttemptOption> options;
  factory AttemptQuestion.fromJson(Map value)=>AttemptQuestion(id:value['id'] as String,type:value['type'] as String,
    prompt:value['prompt'] as String,options:(value['options'] as List? ?? []).cast<Map>().map(AttemptOption.fromJson).toList());
}
class SavedAnswer {
  const SavedAnswer(this.value,this.revision);
  final Map<String,dynamic> value;
  final int revision;
}
class AttemptSnapshot {
  const AttemptSnapshot({required this.id,required this.childId,required this.assignmentId,required this.title,required this.subjectName,
    required this.instructions,required this.status,required this.text,required this.questions,required this.answers,required this.writable,this.attemptNumber=1,this.writtenAnswerMode='typed'});
  final String id,childId,assignmentId,title,subjectName,instructions,text,status;
  final List<AttemptQuestion> questions;
  final Map<String,SavedAnswer> answers;
  final bool writable;
  final int attemptNumber;
  /// Onde responder às perguntas abertas, decidido pelo responsável: 'typed' (na app) ou 'paper' (no caderno).
  final String writtenAnswerMode;
  factory AttemptSnapshot.fromJson(Map value)=>AttemptSnapshot(
    attemptNumber:value['attemptNumber'] as int? ?? 1,
    writtenAnswerMode:value['writtenAnswerMode']=='paper'?'paper':'typed',
    id:value['id'] as String,childId:value['childId'] as String,assignmentId:value['assignmentId'] as String,
    status:value['status'] as String,title:value['title'] as String,subjectName:value['subjectName'] as String,instructions:value['instructions'] as String? ?? '',
    text:value['text'] as String? ?? '',writable:value['writable']==true,
    questions:(value['questions'] as List).cast<Map>().map(AttemptQuestion.fromJson).toList(),
    answers:{for(final answer in (value['answers'] as List).cast<Map>())
      answer['questionId'] as String:SavedAnswer(Map<String,dynamic>.from(answer['answer'] as Map),answer['revision'] as int)},
  );
}
class PendingAnswer {
  const PendingAnswer({required this.operationId,required this.baseRevision,required this.answer});
  final String operationId;
  final int baseRevision;
  final Map<String,dynamic> answer;
  Map<String,dynamic> toJson()=>{'operationId':operationId,'baseRevision':baseRevision,'answer':answer};
  factory PendingAnswer.fromJson(Map value)=>PendingAnswer(operationId:value['operationId'] as String,
    baseRevision:value['baseRevision'] as int,answer:Map<String,dynamic>.from(value['answer'] as Map));
}
