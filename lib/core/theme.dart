import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────

class MarginaliaColors {
  static const background = Color(0xFFFAFAF8);
  static const surface = Color(0xFFF2F0EC);
  static const text = Color(0xFF1A1A18);
  static const textMuted = Color(0xFF6B6862);
  static const accent = Color(0xFF8B7355);
  static const accentLight = Color(0xFFC4A882);
  static const border = Color(0xFFE8E4DF);

  // Highlight colors (Kindle palette)
  static const highlightYellow = Color(0xFFFFF3CD);
  static const highlightBlue = Color(0xFFCCE5FF);
  static const highlightPink = Color(0xFFF8D7DA);
  static const highlightOrange = Color(0xFFFFE0B2);
}

// ─── Typography ──────────────────────────────────────────────────────────────

class MarginaliaTextStyles {
  static TextStyle get highlightBody => GoogleFonts.lora(
        fontSize: 17,
        height: 1.75,
        color: MarginaliaColors.text,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get highlightBodySmall => GoogleFonts.lora(
        fontSize: 15,
        height: 1.7,
        color: MarginaliaColors.text,
      );

  static TextStyle get bookTitle => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.text,
        letterSpacing: -0.3,
      );

  static TextStyle get bookAuthor => const TextStyle(
        fontSize: 13,
        color: MarginaliaColors.textMuted,
        letterSpacing: 0.2,
      );

  static TextStyle get label => const TextStyle(
        fontSize: 12,
        color: MarginaliaColors.textMuted,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get sectionTitle => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.textMuted,
        letterSpacing: 0.8,
      );
}

// ─── Theme ───────────────────────────────────────────────────────────────────

ThemeData buildMarginaliaTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      surface: MarginaliaColors.background,
      surfaceContainerHighest: MarginaliaColors.surface,
      primary: MarginaliaColors.accent,
      onPrimary: Colors.white,
      secondary: MarginaliaColors.accentLight,
      onSurface: MarginaliaColors.text,
      outline: MarginaliaColors.border,
    ),
    scaffoldBackgroundColor: MarginaliaColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: MarginaliaColors.background,
      foregroundColor: MarginaliaColors.text,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: MarginaliaColors.border,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: MarginaliaColors.text,
        letterSpacing: -0.4,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MarginaliaColors.background,
      indicatorColor: MarginaliaColors.accentLight.withAlpha(80),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: MarginaliaColors.accent);
        }
        return const IconThemeData(color: MarginaliaColors.textMuted);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: MarginaliaColors.accent,
          );
        }
        return const TextStyle(
          fontSize: 11,
          color: MarginaliaColors.textMuted,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: MarginaliaColors.border,
      space: 1,
      thickness: 1,
    ),
    cardTheme: CardTheme(
      color: MarginaliaColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MarginaliaColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MarginaliaColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MarginaliaColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MarginaliaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MarginaliaColors.accent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: MarginaliaColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: MarginaliaColors.accent),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MarginaliaColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MarginaliaColors.surface,
      labelStyle: const TextStyle(
        color: MarginaliaColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      side: const BorderSide(color: MarginaliaColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
  );
}
