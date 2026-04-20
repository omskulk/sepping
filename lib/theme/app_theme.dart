import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SepColors {
  static const navy = Color(0xFF1B212C);
  static const darkNavy = Color(0xFF0C141A);
  static const light = Color(0xFFEEEADE);
  static const lightBlue = Color(0xFFD0E4EF);
  static const blueGray = Color(0xFF8FA2C2);
  static const gray = Color(0xFFD2D0D1);
  static const white = Color(0xFFFFFFFF);
  static const success = Color(0xFF3F7D58);
  static const danger = Color(0xFFB63A3A);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    final displayFont = GoogleFonts.bebasNeueTextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

    final textTheme = base.textTheme
        .copyWith(
          displayLarge: displayFont.displayLarge?.copyWith(color: SepColors.navy, letterSpacing: 1.2),
          displayMedium: displayFont.displayMedium?.copyWith(color: SepColors.navy, letterSpacing: 1.2),
          displaySmall: displayFont.displaySmall?.copyWith(color: SepColors.navy, letterSpacing: 1.2),
          headlineLarge: displayFont.headlineLarge?.copyWith(color: SepColors.navy),
          headlineMedium: displayFont.headlineMedium?.copyWith(color: SepColors.navy),
          headlineSmall: displayFont.headlineSmall?.copyWith(color: SepColors.navy),
          titleLarge: bodyFont.titleLarge?.copyWith(color: SepColors.navy, fontWeight: FontWeight.w600),
          titleMedium: bodyFont.titleMedium?.copyWith(color: SepColors.navy, fontWeight: FontWeight.w600),
          titleSmall: bodyFont.titleSmall?.copyWith(color: SepColors.navy, fontWeight: FontWeight.w600),
          bodyLarge: bodyFont.bodyLarge?.copyWith(color: SepColors.darkNavy),
          bodyMedium: bodyFont.bodyMedium?.copyWith(color: SepColors.darkNavy),
          bodySmall: bodyFont.bodySmall?.copyWith(color: SepColors.darkNavy),
          labelLarge: bodyFont.labelLarge?.copyWith(color: SepColors.navy, fontWeight: FontWeight.w600),
        );

    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: SepColors.navy,
        onPrimary: SepColors.light,
        secondary: SepColors.lightBlue,
        onSecondary: SepColors.darkNavy,
        tertiary: SepColors.blueGray,
        surface: SepColors.white,
        onSurface: SepColors.darkNavy,
        error: SepColors.danger,
        onError: SepColors.light,
      ),
      scaffoldBackgroundColor: SepColors.light,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: SepColors.navy,
        foregroundColor: SepColors.light,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: GoogleFonts.bebasNeue(
          color: SepColors.light,
          fontSize: 28,
          letterSpacing: 2.0,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: SepColors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SepColors.navy,
          foregroundColor: SepColors.light,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SepColors.navy,
          side: const BorderSide(color: SepColors.navy, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SepColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SepColors.gray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SepColors.gray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SepColors.navy, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SepColors.lightBlue,
        labelStyle: GoogleFonts.inter(color: SepColors.darkNavy, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: SepColors.gray, thickness: 1),
    );
  }
}
