import 'package:flutter/material.dart';
import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Lexend',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.error,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
                fontSize: 36, height: 1.22, fontWeight: FontWeight.w800),
            headlineMedium: const TextStyle(
                fontSize: 28, height: 1.28, fontWeight: FontWeight.w700),
            titleLarge: const TextStyle(
                fontSize: 22, height: 1.27, fontWeight: FontWeight.w700),
            titleMedium: const TextStyle(
                fontSize: 18, height: 1.33, fontWeight: FontWeight.w600),
            bodyLarge: const TextStyle(fontSize: 17, height: 1.53),
            bodyMedium: const TextStyle(fontSize: 15, height: 1.47),
            labelLarge: const TextStyle(
                fontSize: 16, height: 1.25, fontWeight: FontWeight.w700),
          )
          .apply(
              fontFamily: 'Lexend',
              bodyColor: AppColors.text,
              displayColor: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
            borderSide: const BorderSide(color: AppColors.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.lavender),
    );
  }
}
