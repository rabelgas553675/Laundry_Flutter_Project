import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'constants.dart';

/// Raw brand colors. Everything else in the theme derives from these.
///
/// Monochrome brand identity: black/near-black as the primary action
/// color, with a dark gray secondary step, rather than a hue-based
/// palette. Kept deliberately desaturated end to end so nothing in
/// the UI accidentally reads as "accent colored."
class AppColors {
  AppColors._();

  static const Color primaryLight = Color(0xFF111214); // near-black brand primary
  static const Color primaryDark = Color(0xFFF5F5F5); // near-white, for contrast on dark bg
  static const Color secondaryLight = Color(0xFF3A3A3D); // dark gray
  static const Color secondaryDark = Color(0xFFB0B0B3); // light gray
  static const Color errorLight = Color(0xFFDC2626);
  static const Color errorDark = Color(0xFFF87171);
  static const Color backgroundLight = Color(0xFFF7F7F8); // neutral off-white, no color tint
  static const Color backgroundDark = Color(0xFF0D0D0F); // near-black basin
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1A1A1C);
}

/// App theming — light + dark Material 3 themes with consistent
/// colors, typography, and button/input styling shared everywhere.
///
/// TYPOGRAPHY
/// -----------
/// Headings use Plus Jakarta Sans — a geometric, slightly rounded
/// display face that reads as modern/product-y rather than a default
/// system font. Body text uses Inter, which is built for screen
/// legibility at small sizes and pairs cleanly with Jakarta's more
/// characterful letterforms. A touch of negative letter-spacing on
/// the larger headline sizes tightens them up the way most modern
/// app/marketing type does.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    // IMPORTANT: primary/onPrimary/secondary/onSecondary are set
    // explicitly via copyWith rather than left to ColorScheme.fromSeed
    // to resolve on its own. fromSeed's tonal-palette algorithm treats
    // very dark/near-neutral seed colors ambiguously and can resolve
    // them to an unrelated hue (this is why earlier attempts at a
    // "black" theme rendered as teal everywhere) — explicit overrides
    // guarantee the actual brand color is what's used.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.secondaryLight,
      onSecondary: Colors.white,
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
      primary: AppColors.primaryDark,
      onPrimary: Colors.black,
      secondary: AppColors.secondaryDark,
      onSecondary: Colors.black,
      error: AppColors.errorDark,
      surface: AppColors.surfaceDark,
    );
    return _themeFrom(colorScheme, AppColors.backgroundDark);
  }

  static ThemeData _themeFrom(ColorScheme colorScheme, Color scaffoldBackground) {
    final textTheme = TextTheme(
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: colorScheme.onSurface,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: colorScheme.onSurface,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colorScheme.onSurface,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: colorScheme.onSurface,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: colorScheme.onSurfaceVariant,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
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
        labelStyle: GoogleFonts.inter(fontSize: 15, color: colorScheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, thickness: 1),
    );
  }
}