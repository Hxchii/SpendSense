import 'package:flutter/material.dart';

/// Custom color roles beyond Material's fixed ColorScheme slots.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.paper,
    required this.ink,
    required this.brand,
    required this.brandSoft,
    required this.gradientStart,
    required this.gradientEnd,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.surfaceMuted,
    required this.hairline,
  });

  final Color paper;
  final Color ink;
  final Color brand;
  final Color brandSoft;
  final Color gradientStart;
  final Color gradientEnd;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color surfaceMuted;
  final Color hairline;

  static const light = AppColors(
    paper: Color(0xFFF7FBF2),
    ink: Color(0xFF123A2A),
    brand: Color(0xFF368F3B),
    brandSoft: Color(0xFFDDF4C9),
    gradientStart: Color(0xFF16763D),
    gradientEnd: Color(0xFFA8F33F),
    textPrimary: Color(0xFF123A2A),
    textSecondary: Color(0xFF55705D),
    textMuted: Color(0xFF829888),
    surfaceMuted: Color(0xFFEBF5E4),
    hairline: Color(0x1A123A2A),
  );

  static const dark = AppColors(
    paper: Color(0xFF0C1710),
    ink: Color(0xFFF0F8E9),
    brand: Color(0xFF9BEF49),
    brandSoft: Color(0xFF1E3A25),
    gradientStart: Color(0xFF0B472D),
    gradientEnd: Color(0xFF76C936),
    textPrimary: Color(0xFFF0F8E9),
    textSecondary: Color(0xFFA8BDA8),
    textMuted: Color(0xFF718674),
    surfaceMuted: Color(0xFF14261A),
    hairline: Color(0x1FFFFFFF),
  );

  @override
  AppColors copyWith({
    Color? paper,
    Color? ink,
    Color? brand,
    Color? brandSoft,
    Color? gradientStart,
    Color? gradientEnd,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? surfaceMuted,
    Color? hairline,
  }) {
    return AppColors(
      paper: paper ?? this.paper,
      ink: ink ?? this.ink,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      hairline: hairline ?? this.hairline,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
