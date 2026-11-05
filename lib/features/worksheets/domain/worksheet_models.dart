class SchoolSubject {
  const SchoolSubject(this.id, this.name);
  final String id;
  final String name;
  factory SchoolSubject.fromJson(Map value) => SchoolSubject(value['id'] as String, value['name'] as String);
}
class SchoolTopic {
  const SchoolTopic(this.id, this.name);
  final String id;
  final String name;
  factory SchoolTopic.fromJson(Map value) => SchoolTopic(value['id'] as String, value['name'] as String);
}
class WorksheetSummary {
  const WorksheetSummary({required this.id,required this.versionId,required this.title,required this.subjectName,required this.schoolYear,required this.questionCount,required this.choiceCount,required this.writtenCount,required this.topicNames,required this.isSample});
  final String id,versionId,title,subjectName;
  final int schoolYear,questionCount,choiceCount,writtenCount;
  final List<String> topicNames;
  final bool isSample;
  String get sizeLabel => questionCount<=4 ? 'Curta' : questionCount<=8 ? 'Normal' : 'Longa';
  factory WorksheetSummary.fromJson(Map value) => WorksheetSummary(
    id:value['id'] as String,versionId:value['versionId'] as String,title:value['title'] as String,
    subjectName:value['subjectName'] as String,schoolYear:value['schoolYear'] as int,
    questionCount:value['questionCount'] as int,choiceCount:value['choiceCount'] as int,writtenCount:value['writtenCount'] as int,
    topicNames:(value['topicNames'] as List).cast<String>(),isSample:value['isSample']==true);
}
class AssignedWorksheet {
  const AssignedWorksheet({required this.id,required this.childId,required this.worksheet,required this.assignedAt,this.activeAttemptId,this.latestAttemptId,this.latestAttemptStatus,this.latestAttemptNumber});
  final String id,childId;
  final String? activeAttemptId,latestAttemptId,latestAttemptStatus;
  final int? latestAttemptNumber;
  bool get canRepeat => activeAttemptId==null && latestAttemptId!=null && latestAttemptStatus=='completed';
  final WorksheetSummary worksheet;
  final DateTime assignedAt;
  factory AssignedWorksheet.fromJson(Map value) => AssignedWorksheet(id:value['id'] as String,
    childId:value['childId'] as String,worksheet:WorksheetSummary.fromJson(value['worksheet'] as Map),
    assignedAt:DateTime.parse(value['assignedAt'] as String),activeAttemptId:value['activeAttemptId'] as String?,latestAttemptId:value['latestAttemptId'] as String?,latestAttemptStatus:value['latestAttemptStatus'] as String?,latestAttemptNumber:value['latestAttemptNumber'] as int?);
}
