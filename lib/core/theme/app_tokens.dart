import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF5845CA);
  static const primaryPressed = Color(0xFF432BB4);
  static const lavender = Color(0xFFEDE9FE);
  static const background = Color(0xFFFBF9FF);
  static const surface = Colors.white;
  static const softBlue = Color(0xFFEFF4FF);
  static const blueBorder = Color(0xFFD5E3FC);
  static const text = Color(0xFF0D1C2E);
  static const muted = Color(0xFF474554);
  static const outline = Color(0xFFC9C4D6);
  static const success = Color(0xFF2A6900);
  static const successPressed = Color(0xFF1F5100);
  static const successSoft = Color(0xFFE6F6DA);
  static const coral = Color(0xFFFF7A59);
  static const coralSoft = Color(0xFFFFE5DF);
  static const amber = Color(0xFF855300);
  static const amberSoft = Color(0xFFFFDDB8);
  static const error = Color(0xFFBA1A1A);
}

abstract final class AppSpacing {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 36.0;
  static const maxWidth = 1140.0;
}

abstract final class AppRadii {
  static const card = 28.0;
  static const input = 16.0;
  static const pill = 999.0;
}
