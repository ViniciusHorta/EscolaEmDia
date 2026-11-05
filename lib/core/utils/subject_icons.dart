import 'package:flutter/material.dart';

/// Ícone por disciplina; nomes desconhecidos usam um livro.
IconData subjectIcon(String subject) {
  final name = subject.toLowerCase();
  if (name.contains('matem')) return Icons.calculate_rounded;
  if (name.contains('portugu')) return Icons.menu_book_rounded;
  if (name.contains('meio') || name.contains('ciên') || name.contains('cien')) return Icons.science_rounded;
  if (name.contains('inglês') || name.contains('ingles')) return Icons.translate_rounded;
  if (name.contains('hist') || name.contains('geogr')) return Icons.public_rounded;
  return Icons.auto_stories_rounded;
}
