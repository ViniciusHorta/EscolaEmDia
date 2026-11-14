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
  const WorksheetSummary({required this.id,required this.versionId,required this.title,required this.subjectName,required this.schoolYear,required this.questionCount,required this.choiceCount,required this.writtenCount,required this.topicNames,required this.isSample,this.accessTier='premium',this.timesCompleted,this.lastCompletedAt});
  final String id,versionId,title,subjectName;
  final int schoolYear,questionCount,choiceCount,writtenCount;
  final List<String> topicNames;
  final bool isSample;
  /// free | premium. Fichas Premium só podem ser disponibilizadas a crianças Premium.
  final String accessTier;
  bool get isPremium => accessTier=='premium';
  /// Quantas vezes a criança escolhida já entregou esta ficha (null quando o pedido não indicou criança).
  final int? timesCompleted;
  final DateTime? lastCompletedAt;
  String get sizeLabel => questionCount<=4 ? 'Curta' : questionCount<=8 ? 'Normal' : 'Longa';
  factory WorksheetSummary.fromJson(Map value) => WorksheetSummary(
    id:value['id'] as String,versionId:value['versionId'] as String,title:value['title'] as String,
    subjectName:value['subjectName'] as String,schoolYear:value['schoolYear'] as int,
    questionCount:value['questionCount'] as int,choiceCount:value['choiceCount'] as int,writtenCount:value['writtenCount'] as int,
    topicNames:(value['topicNames'] as List).cast<String>(),isSample:value['isSample']==true,accessTier:value['accessTier'] as String? ?? 'premium',
    timesCompleted:(value['childHistory'] as Map?)?['timesCompleted'] as int?,
    lastCompletedAt:switch((value['childHistory'] as Map?)?['lastCompletedAt']){final String at=>DateTime.parse(at).toLocal(),_=>null});
}
class AssignedWorksheet {
  const AssignedWorksheet({required this.id,required this.childId,required this.worksheet,required this.assignedAt,this.activeAttemptId,this.latestAttemptId,this.latestAttemptStatus,this.latestAttemptNumber,this.latestCompletedAttemptId,this.latestCompletedAttemptNumber});
  final String id,childId;
  final String? activeAttemptId,latestAttemptId,latestAttemptStatus,latestCompletedAttemptId;
  final int? latestAttemptNumber,latestCompletedAttemptNumber;
  bool get canRepeat => activeAttemptId==null && latestAttemptId!=null && latestAttemptStatus=='completed';
  final WorksheetSummary worksheet;
  final DateTime assignedAt;
  factory AssignedWorksheet.fromJson(Map value) => AssignedWorksheet(id:value['id'] as String,
    childId:value['childId'] as String,worksheet:WorksheetSummary.fromJson(value['worksheet'] as Map),
    assignedAt:DateTime.parse(value['assignedAt'] as String),activeAttemptId:value['activeAttemptId'] as String?,latestAttemptId:value['latestAttemptId'] as String?,latestAttemptStatus:value['latestAttemptStatus'] as String?,latestAttemptNumber:value['latestAttemptNumber'] as int?,
    latestCompletedAttemptId:value['latestCompletedAttemptId'] as String?,latestCompletedAttemptNumber:value['latestCompletedAttemptNumber'] as int?);
}
