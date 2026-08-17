import 'package:flutter/material.dart';

/// Custom color roles beyond Material's fixed ColorScheme slots. Deliberately
/// monochrome-first (paper/ink) with a single confident accent — the accent
/// is applied by hand only where it earns its place (nav, links, positive
/// deltas), never smeared across every button/app bar the way a bare
/// `ColorScheme.fromSeed` does.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.paper,
    required this.ink,
    required this.brand,
    required this.brandSoft,
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
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color surfaceMuted;
  final Color hairline;

  static const light = AppColors(
    paper: Color(0xFFFBF9F4),
    ink: Color(0xFF171512),
    brand: Color(0xFF1F6F54),
    brandSoft: Color(0xFFDCEBE3),
    textPrimary: Color(0xFF171512),
    textSecondary: Color(0xFF6B6660),
    textMuted: Color(0xFF9B958C),
    surfaceMuted: Color(0xFFF1EEE6),
    hairline: Color(0x14171512),
  );

  static const dark = AppColors(
    paper: Color(0xFF121110),
    ink: Color(0xFFF5F3EE),
    brand: Color(0xFF4FBE9A),
    brandSoft: Color(0xFF1D362E),
    textPrimary: Color(0xFFF5F3EE),
    textSecondary: Color(0xFFA39D93),
    textMuted: Color(0xFF726C63),
    surfaceMuted: Color(0xFF221F1D),
    hairline: Color(0x1FFFFFFF),
  );

  @override
  AppColors copyWith({
    Color? paper,
    Color? ink,
    Color? brand,
    Color? brandSoft,
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
