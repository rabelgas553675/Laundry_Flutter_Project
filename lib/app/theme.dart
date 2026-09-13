import 'package:flutter/material.dart';

/// Raw brand colors. Everything else in the theme derives from these.
class AppColors {
  AppColors._();

  static const Color primaryLight = Color(0xFF0EA5E9);   // sky blue — water/clean
  static const Color primaryDark = Color(0xFF38BDF8);
  static const Color secondaryLight = Color(0xFF14B8A6);  // teal — freshness
  static const Color secondaryDark = Color(0xFF2DD4BF);
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1E293B);
}

/// App theming — light + dark Material 3 themes with consistent
/// colors, typography, and button/input styling shared everywhere.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight,
      brightness: Brightness.light,
    ).copyWith(
      secondary: AppColors.secondaryLight,
      error: AppColors.errorLight,
      surface: AppColors.surfaceLight,
    );
    return _themeFrom(colorScheme, AppColors.backgroundLight);
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark,
      brightness: Brightness.dark,
    ).copyWith(
      secondary: AppColors.secondaryDark,
      error: AppColors.errorDark,
      surface: AppColors.surfaceDark,
    );
    return _themeFrom(colorScheme, AppColors.backgroundDark);
  }

  static ThemeData _themeFrom(ColorScheme colorScheme, Color scaffoldBackground) {
    final textTheme = TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colorScheme.onSurface),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: colorScheme.onSurface),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: colorScheme.onSurfaceVariant),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: colorScheme.onSurfaceVariant),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size.fromHeight(48),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, thickness: 1),
    );
  }
}