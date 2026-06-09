import 'package:flutter/material.dart';

// google_fonts removed — using system font to avoid build issues.
// Re-add: import 'package:google_fonts/google_fonts.dart'; and
// replace _interText() calls once fonts are confirmed working.

enum AppThemeVariant { light, dark, goldBlack }

class AppTheme {
  // ── Brand Colors ────────────────────────────────────────────
  static const Color primaryBlue   = Color(0xFF2563EB);
  static const Color primaryDark   = Color(0xFF1D4ED8);
  static const Color accentGreen   = Color(0xFF10B981);
  static const Color accentOrange  = Color(0xFFF59E0B);
  static const Color accentRed     = Color(0xFFEF4444);
  static const Color accentPurple  = Color(0xFF8B5CF6);

  // Light surface
  static const Color surfaceLight  = Color(0xFFF8FAFC);
  static const Color cardLight     = Color(0xFFFFFFFF);
  static const Color borderLight   = Color(0xFFE2E8F0);

  // Dark surface
  static const Color surfaceDark   = Color(0xFF0F172A);
  static const Color cardDark      = Color(0xFF1E293B);
  static const Color borderDark    = Color(0xFF334155);

  // Gold & Black surface
  static const Color goldPrimary   = Color(0xFFD4AF37);
  static const Color goldAccent    = Color(0xFFF5C842);
  static const Color goldMuted     = Color(0xFF8B6914);
  static const Color surfaceGold   = Color(0xFF0A0A0A);
  static const Color cardGold      = Color(0xFF141414);
  static const Color cardGoldRaise = Color(0xFF1E1E1E);
  static const Color borderGold    = Color(0xFF2A2A2A);

  // ── Light Theme ─────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        surface: surfaceLight,
        surfaceContainerHighest: cardLight,
      ),
      scaffoldBackgroundColor: surfaceLight,
      textTheme: base.textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: cardLight,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderLight),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: primaryBlue),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accentRed),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: Color(0xFF64748B)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEFF6FF),
        labelStyle: const TextStyle(color: primaryBlue, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: borderLight, thickness: 1),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: cardLight,
        selectedIconTheme: IconThemeData(color: primaryBlue),
        unselectedIconTheme: IconThemeData(color: Color(0xFF94A3B8)),
        indicatorColor: Color(0xFFEFF6FF),
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        surface: surfaceDark,
        surfaceContainerHighest: cardDark,
      ),
      scaffoldBackgroundColor: surfaceDark,
      textTheme: base.textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: cardDark,
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600,
          color: Color(0xFFF1F5F9),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderDark),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      dividerTheme: const DividerThemeData(color: borderDark, thickness: 1),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: cardDark,
        selectedIconTheme: IconThemeData(color: primaryBlue),
        unselectedIconTheme: IconThemeData(color: Color(0xFF64748B)),
        indicatorColor: Color(0xFF1E3A5F),
      ),
    );
  }

  // ── Gold & Black Theme ───────────────────────────────────────
  static ThemeData get goldBlackTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary:            goldPrimary,
        onPrimary:          Colors.black,
        secondary:          goldAccent,
        onSecondary:        Colors.black,
        error:              accentRed,
        onError:            Colors.white,
        surface:            surfaceGold,
        onSurface:          Color(0xFFF0E6C8),
        surfaceContainerHighest: cardGold,
        outline:            borderGold,
      ),
      scaffoldBackgroundColor: surfaceGold,
      textTheme: base.textTheme.apply(
        bodyColor:    const Color(0xFFF0E6C8),
        displayColor: const Color(0xFFF0E6C8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cardGold,
        foregroundColor: goldPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: goldPrimary, letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: goldPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardGold,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderGold),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: goldPrimary,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: goldPrimary,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: goldPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardGoldRaise,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderGold),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderGold),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: goldPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accentRed),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: Color(0xFF8B7A45)),
        hintStyle: const TextStyle(color: Color(0xFF5A4D2A)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardGoldRaise,
        labelStyle: const TextStyle(color: goldPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: borderGold),
        ),
        padding: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: borderGold, thickness: 1),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: cardGold,
        selectedIconTheme: IconThemeData(color: goldPrimary),
        unselectedIconTheme: IconThemeData(color: Color(0xFF5A4D2A)),
        indicatorColor: Color(0xFF2A2200),
        selectedLabelTextStyle: TextStyle(color: goldPrimary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: Color(0xFF5A4D2A)),
      ),
      iconTheme: const IconThemeData(color: goldPrimary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? goldPrimary : borderGold,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? goldPrimary.withOpacity(0.3)
              : cardGoldRaise,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: goldPrimary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: goldPrimary,
        foregroundColor: Colors.black,
      ),
    );
  }
}

/// Common text styles
class AppTextStyles {
  static const heading1 = TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static const heading2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3);
  static const heading3 = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4);
  static const body     = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const bodyMed  = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const caption  = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const label    = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5);
}

/// Status badge colors
class StatusColors {
  static Color forStatus(String status) => switch (status.toLowerCase()) {
    'present'  => AppTheme.accentGreen,
    'late'     => AppTheme.accentOrange,
    'absent'   => AppTheme.accentRed,
    'half_day' => AppTheme.accentPurple,
    'on_leave' => AppTheme.primaryBlue,
    _          => const Color(0xFF94A3B8),
  };
}
