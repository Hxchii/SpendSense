import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/data_palette.dart';

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

class AppTheme {
  AppTheme._();

  /// Income (positive delta) uses the palette's success/delta-good text
  /// color; expense uses the categorical "red" slot rather than the
  /// reserved status-critical hex — a normal expense entry isn't an alarm.
  static Color income(Brightness brightness) => DataPalette.deltaGood(brightness);
  static Color expense(Brightness brightness) => DataPalette.categorical(7, brightness);

  static ThemeData light() => _themeFrom(AppColors.light, Brightness.light);
  static ThemeData dark() => _themeFrom(AppColors.dark, Brightness.dark);

  static ThemeData _themeFrom(AppColors colors, Brightness brightness) {
    final scheme = brightness == Brightness.light
        ? ColorScheme(
            brightness: Brightness.light,
            primary: colors.ink,
            onPrimary: colors.paper,
            secondary: colors.brand,
            onSecondary: colors.paper,
            error: DataPalette.statusCritical,
            onError: Colors.white,
            surface: Colors.white,
            onSurface: colors.textPrimary,
            surfaceContainerHighest: colors.surfaceMuted,
            surfaceContainerHigh: colors.surfaceMuted,
            outline: colors.hairline,
            onSurfaceVariant: colors.textSecondary,
          )
        : ColorScheme(
            brightness: Brightness.dark,
            primary: colors.ink,
            onPrimary: colors.paper,
            secondary: colors.brand,
            onSecondary: colors.paper,
            error: DataPalette.statusCritical,
            onError: Colors.white,
            surface: const Color(0xFF1C1A18),
            onSurface: colors.textPrimary,
            surfaceContainerHighest: colors.surfaceMuted,
            surfaceContainerHigh: colors.surfaceMuted,
            outline: colors.hairline,
            onSurfaceVariant: colors.textSecondary,
          );

    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.paper,
      extensions: [colors],
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colors.hairline),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceMuted,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.paper,
          disabledBackgroundColor: colors.textMuted,
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.paper,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.brand,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: colors.textPrimary)),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceMuted,
        selectedColor: colors.brandSoft,
        labelStyle: textTheme.labelMedium?.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: colors.brand, fontWeight: FontWeight.w700),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.brand : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.brandSoft : colors.surfaceMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.brand : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colors.brand : colors.textMuted,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.brand, circularTrackColor: colors.surfaceMuted),
      dividerTheme: DividerThemeData(color: colors.hairline, space: 1, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: colors.brandSoft,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colors.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      listTileTheme: ListTileThemeData(iconColor: colors.textSecondary, textColor: colors.textPrimary),
    );
  }

  static TextTheme _textTheme(AppColors colors) {
    final display = GoogleFonts.spaceGroteskTextTheme();
    final body = GoogleFonts.manropeTextTheme();

    return body
        .copyWith(
          displayLarge: display.displayLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.5),
          displayMedium: display.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
          displaySmall: display.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: colors.textPrimary, displayColor: colors.textPrimary);
  }
}
