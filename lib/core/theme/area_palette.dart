import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Cores de cada área da app, para se perceber logo onde se está:
/// - [child]: espaço do aluno e escolha de perfil (cor da marca);
/// - [parent]: área do responsável (laranja).
///
/// Os widgets leem a paleta com `context.area`; fora de uma [AreaTheme] usa-se a da marca.
@immutable
class AreaPalette extends ThemeExtension<AreaPalette> {
  const AreaPalette({
    required this.primary,
    required this.primaryPressed,
    required this.tint,
    required this.soft,
    required this.border,
    required this.ring,
    required this.background,
  });

  /// Cor principal (botões, títulos de destaque, seleção).
  final Color primary;
  /// Sombra/estado premido dos botões principais.
  final Color primaryPressed;
  /// Fundo suave de destaque (avatares, indicador da navegação, contornos de cartão).
  final Color tint;
  /// Fundo de botões secundários e chips.
  final Color soft;
  /// Contorno/sombra dos botões secundários.
  final Color border;
  /// Anel à volta de avatares selecionados.
  final Color ring;
  /// Fundo dos ecrãs.
  final Color background;

  static const child = AreaPalette(
    primary: AppColors.primary,
    primaryPressed: AppColors.primaryPressed,
    tint: AppColors.lavender,
    soft: AppColors.softBlue,
    border: AppColors.blueBorder,
    ring: Color(0xFFC7BFFF),
    background: AppColors.background,
  );

  static const parent = AreaPalette(
    primary: Color(0xFFB4540A),
    primaryPressed: Color(0xFF8A3F06),
    tint: Color(0xFFFFE9D1),
    soft: Color(0xFFFFF3E6),
    border: Color(0xFFF6D3AE),
    ring: Color(0xFFF5C08A),
    background: Color(0xFFFFF9F2),
  );

  @override
  AreaPalette copyWith({Color? primary, Color? primaryPressed, Color? tint, Color? soft,
      Color? border, Color? ring, Color? background}) => AreaPalette(
    primary: primary ?? this.primary,
    primaryPressed: primaryPressed ?? this.primaryPressed,
    tint: tint ?? this.tint,
    soft: soft ?? this.soft,
    border: border ?? this.border,
    ring: ring ?? this.ring,
    background: background ?? this.background,
  );

  @override
  AreaPalette lerp(AreaPalette? other, double t) {
    if (other == null) return this;
    return AreaPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      border: Color.lerp(border, other.border, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      background: Color.lerp(background, other.background, t)!,
    );
  }
}

extension AreaPaletteContext on BuildContext {
  /// Paleta da área atual (marca/espaço infantil por omissão).
  AreaPalette get area => Theme.of(this).extension<AreaPalette>() ?? AreaPalette.child;
}

/// Aplica a paleta de uma área a tudo o que está por baixo (incluindo folhas e diálogos
/// abertos a partir daqui, que capturam o tema).
class AreaTheme extends StatelessWidget {
  const AreaTheme({super.key, required this.palette, required this.child});
  final AreaPalette palette;
  final Widget child;

  static ThemeData apply(ThemeData base, AreaPalette palette) => base.copyWith(
    scaffoldBackgroundColor: palette.background,
    // Tons derivados (contentores, seleção, indicadores) coerentes com a cor da área.
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.primary,
      primary: palette.primary,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.error,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.input),
        borderSide: BorderSide(color: palette.primary, width: 2)),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: palette.tint),
    extensions: [palette],
  );

  @override
  Widget build(BuildContext context) =>
      Theme(data: apply(Theme.of(context), palette), child: child);
}
