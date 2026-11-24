// Visão de Aprendizagem (PRD v1.0). O servidor devolve contagens por eixo;
// os índices, estados e evolução são calculados aqui, iguais em todas as plataformas.
import 'dart:math' as math;

/// Período de análise. Só [days30] está disponível no plano Gratuito.
enum LearningPeriod {
  days7('7d', '7 dias', 'Últimos 7 dias'),
  days30('30d', '30 dias', 'Últimos 30 dias'),
  days90('90d', '90 dias', 'Últimos 90 dias'),
  year('year', 'Ano escolar', 'Ano escolar');

  const LearningPeriod(this.code, this.shortLabel, this.label);
  final String code, shortLabel, label;
  bool get freeAvailable => this == days30;
  static LearningPeriod fromCode(String? code) =>
      values.firstWhere((p) => p.code == code, orElse: () => days30);
}

/// Estado do desempenho de um eixo (PRD §13.1).
enum PerformanceState { none, initial, available }

/// Apresentação global do radar consoante as fichas entregues no período (PRD §13.2).
enum RadarState { empty, initial, normal }

/// Limiares de produto (sujeitos a validação — PRD §25.1).
abstract final class LearningThresholds {
  static const balanceReference = 0.8; // RN-P08
  static const enoughEvaluated = 20; // §13.1 / RN-E01 / RN-S05
  static const enoughAttempts = 10; // §13.2
}

/// Respostas avaliadas: corretas, parcialmente corretas e incorretas (pendentes ficam de fora).
class AnswerCounts {
  const AnswerCounts({this.correct = 0, this.partial = 0, this.incorrect = 0});
  final int correct, partial, incorrect;
  int get evaluated => correct + partial + incorrect;

  /// D = (C + 0,5·P) / A · 100. Null quando não há perguntas avaliadas (nunca 0%).
  double? get performance => evaluated == 0 ? null : (correct + partial * 0.5) / evaluated * 100;

  PerformanceState get state => evaluated == 0
      ? PerformanceState.none
      : evaluated < LearningThresholds.enoughEvaluated
          ? PerformanceState.initial
          : PerformanceState.available;

  static int _n(Object? v) => v is num ? v.toInt() : 0;
  factory AnswerCounts.fromJson(Map value) =>
      AnswerCounts(correct: _n(value['correct']), partial: _n(value['partial']), incorrect: _n(value['incorrect']));
}

class LearningAxis {
  const LearningAxis({required this.id, required this.name, required this.attempts, required this.exercises,
    required this.answers, required this.pending, required this.practice, this.previous});
  final String id, name;
  /// Fichas entregues (todas as tentativas) e exercícios realizados no período.
  final int attempts, exercises;
  /// Respostas avaliadas da tentativa mais recente de cada ficha.
  final AnswerCounts answers;
  /// Respostas por rever no período.
  final int pending;
  /// Índice de prática, 0–100.
  final double practice;
  /// Respostas avaliadas do período anterior (só Premium e sem «ano escolar»).
  final AnswerCounts? previous;

  double? get performance => answers.performance;
  PerformanceState get state => answers.state;

  /// Evolução em pontos percentuais (RN-E01..E04): os dois períodos precisam de 20+ perguntas avaliadas.
  int? get evolution {
    final before = previous;
    if (before == null || state != PerformanceState.available || before.state != PerformanceState.available) return null;
    return performance!.round() - before.performance!.round();
  }
}

/// Índices de prática (PRD §9.3): normaliza pela média/0,8 ou pelo máximo, o que for maior.
List<double> practiceIndices(List<int> exercises) {
  if (exercises.isEmpty) return const [];
  final total = exercises.fold<int>(0, (a, b) => a + b);
  if (total == 0) return List.filled(exercises.length, 0);
  final reference = total / exercises.length / LearningThresholds.balanceReference;
  final limit = math.max(reference, exercises.reduce(math.max).toDouble());
  return [for (final q in exercises) math.min(100, q / limit * 100)];
}

class LearningOverview {
  const LearningOverview({required this.childId, required this.childName, required this.schoolYear,
    required this.isPremium, required this.period, required this.completedAttempts, required this.axes,
    this.subjectId, this.subjectName});
  final String childId, childName;
  final int schoolYear;
  final bool isPremium;
  final LearningPeriod period;
  /// Fichas entregues no período (todas as tentativas).
  final int completedAttempts;
  final List<LearningAxis> axes;
  /// Preenchido quando o radar é por tema (dentro de uma disciplina).
  final String? subjectId, subjectName;

  bool get byTopic => subjectId != null;
  int get pending => axes.fold(0, (a, b) => a + b.pending);

  RadarState get radarState => completedAttempts == 0
      ? RadarState.empty
      : completedAttempts < LearningThresholds.enoughAttempts
          ? RadarState.initial
          : RadarState.normal;

  factory LearningOverview.fromJson(Map value) {
    final child = value['child'] as Map;
    final raw = (value['axes'] as List).cast<Map>();
    final indices = practiceIndices([for (final a in raw) (a['exercises'] as num).toInt()]);
    final subject = value['subject'];
    return LearningOverview(
      childId: child['id'] as String, childName: child['displayName'] as String,
      schoolYear: (child['schoolYear'] as num).toInt(), isPremium: value['plan'] == 'premium',
      period: LearningPeriod.fromCode(value['period'] as String?),
      completedAttempts: (value['completedAttempts'] as num?)?.toInt() ?? 0,
      subjectId: subject is Map ? subject['id'] as String : null,
      subjectName: subject is Map ? subject['name'] as String : null,
      axes: [
        for (var i = 0; i < raw.length; i++)
          LearningAxis(
            id: raw[i]['id'] as String, name: raw[i]['name'] as String,
            attempts: (raw[i]['attempts'] as num).toInt(), exercises: (raw[i]['exercises'] as num).toInt(),
            answers: AnswerCounts.fromJson(raw[i]), pending: (raw[i]['pending'] as num).toInt(),
            practice: indices[i],
            previous: raw[i]['previous'] is Map ? AnswerCounts.fromJson(raw[i]['previous'] as Map) : null,
          ),
      ],
    );
  }
}

/// Texto de percentagem arredondada, ou «—» quando não há valor.
String percentLabel(double? value) => value == null ? '—' : '${value.round()}%';

String evolutionLabel(int value) => value > 0 ? '+$value p.p.' : '$value p.p.';

/// Tipo de sugestão, pela ordem de prioridade do PRD (§16.5).
enum SuggestionKind { review, reinforce, consolidate, moreData, maintain }

class StudySuggestion {
  const StudySuggestion(this.kind, this.axis);
  final SuggestionKind kind;
  final LearningAxis axis;

  String get title => switch (kind) {
    SuggestionKind.review => 'Rever ${axis.name}',
    SuggestionKind.reinforce => 'Praticar ${axis.name}',
    SuggestionKind.consolidate => 'Consolidar ${axis.name}',
    SuggestionKind.moreData => 'Explorar ${axis.name}',
    SuggestionKind.maintain => 'Manter ${axis.name}',
  };
  String get reason => switch (kind) {
    SuggestionKind.review => 'Apesar da prática regular, alguns conteúdos podem beneficiar de uma revisão acompanhada.',
    SuggestionKind.reinforce => 'Mais exercícios poderão ajudar a consolidar os conteúdos trabalhados.',
    SuggestionKind.consolidate => 'Os resultados vão no bom caminho. Mais alguma prática ajuda a consolidar os conhecimentos.',
    SuggestionKind.moreData => 'Ainda não existem exercícios avaliados suficientes para compreender o desempenho neste conteúdo.',
    SuggestionKind.maintain => 'Bons resultados, com pouca prática neste período. Uma atividade curta ajuda a manter os conhecimentos.',
  };
}

enum _Level { low, mid, high }
_Level _performanceLevel(double v) => v < 60 ? _Level.low : v < 80 ? _Level.mid : _Level.high;
_Level _practiceLevel(double v) => v < 50 ? _Level.low : v < 80 ? _Level.mid : _Level.high;

/// Sugestão para um eixo (§16.4), ou null quando não há nada relevante a sugerir.
/// - Sem prática no período: nada (RN-S06/S07 — não se assume dificuldade nem que já foi lecionado).
/// - Menos de 20 perguntas avaliadas: só «realizar mais exercícios» (RN-S05).
/// - Desempenho baixo com prática intermédia (HP06, por validar): tratado como «reforçar».
SuggestionKind? suggestionFor(LearningAxis axis) {
  if (axis.exercises == 0) return null;
  if (axis.state != PerformanceState.available) return SuggestionKind.moreData;
  final performance = _performanceLevel(axis.performance!), practice = _practiceLevel(axis.practice);
  return switch (performance) {
    _Level.low => practice == _Level.high ? SuggestionKind.review : SuggestionKind.reinforce,
    _Level.mid => SuggestionKind.consolidate,
    _Level.high => practice == _Level.low ? SuggestionKind.maintain : null,
  };
}

/// Até 3 sugestões por prioridade (RN-S01). Desempate (HP05, por validar): menor desempenho primeiro;
/// em «mais dados», o eixo com mais exercícios; depois o nome.
List<StudySuggestion> studySuggestions(List<LearningAxis> axes) {
  final items = [for (final a in axes) if (suggestionFor(a) case final kind?) StudySuggestion(kind, a)];
  items.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    final pa = a.axis.performance, pb = b.axis.performance;
    if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
    if (a.axis.exercises != b.axis.exercises) return b.axis.exercises.compareTo(a.axis.exercises);
    return a.axis.name.compareTo(b.axis.name);
  });
  return items.take(3).toList();
}
