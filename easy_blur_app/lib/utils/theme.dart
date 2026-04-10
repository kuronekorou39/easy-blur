import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgPrimary = Color(0xFF0f0f1a);
  static const Color bgSecondary = Color(0xFF161625);
  static const Color bgTertiary = Color(0xFF1e1e32);
  static const Color bgHover = Color(0xFF262640);
  static const Color borderColor = Color(0xFF2a2a45);
  static const Color borderLight = Color(0xFF3a3a58);
  static const Color textPrimary = Color(0xFFe8e8f0);
  static const Color textSecondary = Color(0xFF9898b0);
  static const Color textMuted = Color(0xFF686880);
  static const Color accent = Color(0xFF6c5ce7);
  static const Color accentHover = Color(0xFF7d6ff0);
  static const Color danger = Color(0xFFe74c5c);

  // Glass morphism & overlay
  static Color get surfaceGlass => bgSecondary.withValues(alpha: 0.85);
  static const Color sheetBackground = Color(0xFF181830);
  static const double sheetRadius = 16.0;
  static const double toolbarRadius = 14.0;

  // Handle sizes
  static const double handleSize = 14.0;
  static const double handleTouchArea = 28.0;
  static const double rotateHandleDistance = 34.0;

  // Animation durations
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 350);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentHover,
        surface: bgSecondary,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: bgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: borderColor),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textSecondary),
        bodySmall: TextStyle(color: textMuted),
      ),
    );
  }
}
