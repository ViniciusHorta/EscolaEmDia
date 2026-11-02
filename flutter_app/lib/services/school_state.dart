import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/exercise.dart';
import 'exercise_api.dart';

class Attempt {
  Attempt({Map<String, String>? answers, this.checked = false})
    : answers = answers ?? {};
  final Map<String, String> answers;
  bool checked;
  Map<String, dynamic> toJson() => {'answers': answers, 'checked': checked};
  factory Attempt.fromJson(Map value) => Attempt(
    answers: (value['answers'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    checked: value['checked'] == true,
  );
}

class StudySession {
  StudySession({
    required this.startedAt,
    this.active = true,
    Map<String, String>? results,
    Map<String, Attempt>? progress,
  }) : results = results ?? {},
       progress = progress ?? {};
  final DateTime startedAt;
  bool active;
  final Map<String, String> results;
  final Map<String, Attempt> progress;
  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'active': active,
    'results': results,
    'progress': progress.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory StudySession.fromJson(Map value) => StudySession(
    startedAt: DateTime.parse(value['startedAt'] as String),
    active: value['active'] == true,
    results: (value['results'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    progress: (value['progress'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), Attempt.fromJson(value as Map)),
    ),
  );
}

class SchoolState extends ChangeNotifier {
  SchoolState({required this.api, this.preferences}) {
    _restore();
  }
  static const storageKey = 'escola-em-dia-flutter-v1';
  final ExerciseApi api;
  final SharedPreferences? preferences;
  List<Exercise> exercises = [];
  final Map<String, Attempt> freeProgress = {};
  final Map<String, StudySession> sessions = {};
  bool loading = false;
  String? error;
  String? persistenceError;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  List<String> get subjects =>
      exercises.map((e) => e.subject).toSet().toList()..sort();
  List<Exercise> forSubject(String subject) =>
      exercises.where((e) => e.subject == subject).toList();

  void _restore() {
    if (preferences == null) {
      persistenceError = 'O armazenamento local está indisponível. As respostas ficam apenas nesta execução.';
      return;
    }
    try {
      final value =
          jsonDecode(preferences!.getString(storageKey) ?? '{}') as Map;
      final restoredProgress = (value['progress'] as Map? ?? {}).map(
        (key, value) =>
            MapEntry(key.toString(), Attempt.fromJson(value as Map)),
      );
      final restoredSessions = (value['sessions'] as Map? ?? {}).map(
        (key, value) =>
            MapEntry(key.toString(), StudySession.fromJson(value as Map)),
      );
      freeProgress.addAll(restoredProgress);
      sessions.addAll(restoredSessions);
    } catch (_) {
      persistenceError = 'Não foi possível recuperar o progresso guardado. Os exercícios continuam disponíveis.';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> persist() {
    if (preferences == null) return Future.value();
    final snapshot = jsonEncode({
      'progress': freeProgress.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'sessions': sessions.map((key, value) => MapEntry(key, value.toJson())),
    });
    _writes = _writes.then((_) async {
      try {
        if (!await preferences!.setString(storageKey, snapshot))
          throw Exception('Falha ao guardar.');
        persistenceError = null;
      } catch (_) {
        persistenceError = 'Não foi possível guardar o progresso. Mantém esta janela aberta para não perder a sessão.';
      }
      _notify();
    });
    return _writes;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      exercises = await api.load();
    } catch (e) {
      error =
          'Não foi possível carregar os exercícios. Confirma que o servidor Node está ligado.\n$e';
    }
    loading = false;
    _notify();
  }

  Future<Exercise> create(String json) async {
    final exercise = await api.create(json);
    exercises = [...exercises, exercise];
    _notify();
    return exercise;
  }

  bool inSession(Exercise exercise) =>
      sessions[exercise.subject]?.active == true;
  Attempt attempt(Exercise exercise) {
    final target = inSession(exercise)
        ? sessions[exercise.subject]!.progress
        : freeProgress;
    return target.putIfAbsent(exercise.id, () => Attempt());
  }

  void answer(Exercise exercise, String question, String answer) {
    final current = attempt(exercise);
    current.answers[question] = answer;
    current.checked = false;
    _notify();
    persist();
  }

  void validate(Exercise exercise) {
    final current = attempt(exercise);
    current.checked = true;
    if (inSession(exercise))
      sessions[exercise.subject]!.results[exercise.id] = exercise.result(
        current.answers,
      );
    _notify();
    persist();
  }

  void reset(Exercise exercise) {
    final current = attempt(exercise);
    current.answers.clear();
    current.checked = false;
    _notify();
    persist();
  }

  void startSession(String subject) {
    sessions[subject] = StudySession(startedAt: DateTime.now());
    _notify();
    persist();
  }

  void finishSession(String subject) {
    final session = sessions[subject];
    if (session == null) return;
    session.active = false;
    for (final entry in session.progress.entries) {
      freeProgress[entry.key] = Attempt(
        answers: Map.of(entry.value.answers),
        checked: entry.value.checked,
      );
    }
    _notify();
    persist();
  }

  void review(Exercise exercise, String result) {
    if (!inSession(exercise) ||
        !attempt(exercise).checked ||
        !exercise.hasWriting)
      return;
    if (!['correct', 'wrong'].contains(result)) return;
    if (result == 'correct' &&
        exercise.correctCount(attempt(exercise).answers) !=
            exercise.choices.length)
      return;
    sessions[exercise.subject]!.results[exercise.id] = result;
    _notify();
    persist();
  }

  Map<String, int> counts(String subject) {
    final values = forSubject(subject)
        .map((e) => sessions[subject]?.results[e.id]);
    return {
      for (final status in ['correct', 'wrong', 'review'])
        status: values.where((v) => v == status).length,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    api.close();
    super.dispose();
  }
}
