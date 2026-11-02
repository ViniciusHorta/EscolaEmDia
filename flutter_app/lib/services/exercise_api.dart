import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/exercise.dart';

class ExerciseApi {
  ExerciseApi({String? baseUrl, http.Client? client})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:3001',
          ),
      client = client ?? http.Client();
  final String baseUrl;
  final http.Client client;
  Uri get endpoint =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/exercises');

  Future<List<Exercise>> load() async {
    final response = await client
        .get(endpoint)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw Exception(
        'Não foi possível carregar os exercícios (${response.statusCode}).',
      );
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! List)
      throw const FormatException('A lista recebida é inválida.');
    return value.map(Exercise.fromJson).toList();
  }

  Future<Exercise> create(String source) async {
    final value = Exercise.fromJson(jsonDecode(source));
    final response = await client
        .post(
          endpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(value.json),
        )
        .timeout(const Duration(seconds: 15));
    final result = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 201) {
      throw Exception(
        result is Map
            ? result['error'] ?? 'Erro ao guardar.'
            : 'Erro ao guardar.',
      );
    }
    return Exercise.fromJson(result);
  }

  void close() => client.close();
}
