// ─────────────────────────────────────────────────────────────────────────────
//  Lumi · design tokens + theme
//  Drop this in:  lib/theme/lumi_theme.dart
//  Requires:      google_fonts: ^6.2.1   (add to pubspec, then `flutter pub get`)
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// All Lumi colors live here so the whole app stays consistent.
class LumiColors {
  LumiColors._();

  // Backgrounds (Midnight)
  static const bgDeep = Color(0xFF06080E); // page / behind everything
  static const bgTop = Color(0xFF131C30); // gradient top of a screen
  static const bgBottom = Color(0xFF090D18); // gradient bottom of a screen

  // Surfaces / cards
  static const surface = Color(0xFF161E30); // raised card
  static const surface2 = Color(0xFF11192A); // list row / inset
  static const field = Color(0xFF141C2E); // input fields
  static const hairline = Color(0x14FFFFFF); // ~8% white border

  // Text
  static const text = Color(0xFFEAEEF7);
  static const textSub = Color(0xFF94A0B8);
  static const textFaint = Color(0xFF5C6680);

  // Signal Red (alert / primary)
  static const accent = Color(0xFFFF2E45);
  static const accentDeep = Color(0xFFD81B33);

  // Status
  static const green = Color(0xFF25D07D); // "sent / live / safe"
  static const greenSoft = Color(0xFF7DE9B5);
  static const amber = Color(0xFFFFB02E); // siren / caution
  static const blue = Color(0xFF5B8DEF); // message / info

  // Gradients
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDeep],
  );

  /// Full-screen vertical background used by every screen.
  static const screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgBottom],
    stops: [0.0, 0.62],
  );
}

/// Convenience text styles (Space Grotesk = display, Manrope = body).
class LumiText {
  LumiText._();

  static TextStyle display(double size,
          {FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        height: 1.05,
        letterSpacing: -0.4,
        color: color ?? LumiColors.text,
      );

  static TextStyle body(double size,
          {FontWeight weight = FontWeight.w500, Color? color}) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color ?? LumiColors.text,
      );
}

class LumiTheme {
  LumiTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: LumiColors.accent,
      onPrimary: Colors.white,
      secondary: LumiColors.green,
      error: LumiColors.accent,
      surface: LumiColors.surface,
      onSurface: LumiColors.text,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: LumiColors.bgDeep,
      textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme)
          .apply(bodyColor: LumiColors.text, displayColor: LumiColors.text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: LumiColors.text,
      ),
    );

    return base.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LumiColors.field,
        hintStyle: LumiText.body(15, color: LumiColors.textFaint),
        labelStyle: LumiText.body(15, color: LumiColors.textSub),
        prefixIconColor: LumiColors.textFaint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: LumiColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: LumiColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: LumiColors.accent, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LumiColors.surface,
        contentTextStyle: LumiText.body(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
