import 'package:flutter/material.dart';

class AppTheme {
  // ===== カラーシステム =====
  // 背景階層（深い黒から微かに明るい紫までグラデーション）
  static const Color bgPrimary = Color(0xFF0A0A14);
  static const Color bgSecondary = Color(0xFF13131F);
  static const Color bgTertiary = Color(0xFF1C1C2E);
  static const Color bgElevated = Color(0xFF242438);
  static const Color bgHover = Color(0xFF2D2D45);
  static const Color bgActive = Color(0xFF35354F);

  // ボーダー
  static const Color borderColor = Color(0xFF26263E);
  static const Color borderLight = Color(0xFF35355A);
  static const Color borderStrong = Color(0xFF4A4A6E);

  // テキスト（WCAG AA相当のコントラスト）
  static const Color textPrimary = Color(0xFFF2F2F8);
  static const Color textSecondary = Color(0xFFB4B4C8);
  static const Color textMuted = Color(0xFF7878A0);
  static const Color textDisabled = Color(0xFF4A4A66);

  // アクセント（紫グラデーション）
  static const Color accent = Color(0xFF7C6FF0);
  static const Color accentBright = Color(0xFF9D8CFF);
  static const Color accentDark = Color(0xFF5B4FD0);
  static const Color accentSubtle = Color(0x297C6FF0);

  // 状態色
  static const Color success = Color(0xFF4ECDC4);
  static const Color warning = Color(0xFFFFB84D);
  static const Color danger = Color(0xFFFF5E6C);
  static const Color info = Color(0xFF5EB8FF);

  // グラス効果
  static Color get surfaceGlass => bgSecondary.withValues(alpha: 0.82);
  static Color get surfaceGlassStrong => bgSecondary.withValues(alpha: 0.94);
  static const Color sheetBackground = Color(0xFF151525);

  // ===== 形状 =====
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;
  static const double sheetRadius = 24.0;
  static const double toolbarRadius = 16.0;

  // ===== 余白 =====
  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 24.0;
  static const double space2xl = 32.0;

  // ===== ハンドル =====
  static const double handleSize = 14.0;
  static const double handleTouchArea = 32.0;
  static const double rotateHandleDistance = 36.0;

  // ===== アニメーション =====
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 260);
  static const Duration animSlow = Duration(milliseconds: 380);
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeOutQuint;

  // ===== シャドウ =====
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
  static List<BoxShadow> get shadowGlow => [
        BoxShadow(
          color: accent.withValues(alpha: 0.35),
          blurRadius: 20,
          spreadRadius: 0,
        ),
      ];

  // ===== タイポグラフィ =====
  static const TextStyle textDisplay = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    color: textPrimary,
    height: 1.1,
  );
  static const TextStyle textTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: textPrimary,
  );
  static const TextStyle textHeader = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle textBody = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    height: 1.4,
  );
  static const TextStyle textBodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );
  static const TextStyle textCaption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMuted,
    letterSpacing: 0.2,
  );
  static const TextStyle textLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.8,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentBright,
        surface: bgSecondary,
        error: danger,
        onSurface: textPrimary,
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
          borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
          side: BorderSide(color: borderColor),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        displayLarge: textDisplay,
        titleLarge: textTitle,
        titleMedium: textHeader,
        bodyLarge: textBodyStrong,
        bodyMedium: textBody,
        bodySmall: textCaption,
        labelSmall: textLabel,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: bgTertiary,
        thumbColor: accentBright,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 2,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      ),
    );
  }
}
