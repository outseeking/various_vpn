/// Тема Various VPN. Тёмная тема — основная (бренд), светлая — на всякий случай
/// (система может попросить). Шрифты: Orbitron (заголовки) + Rajdhani (текст).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

class AppTheme {
  static TextTheme _textTheme(Brightness b) {
    final base = b == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    // Exo 2 — техно-шрифт с полной поддержкой кириллицы И латиницы, поэтому
    // русский и английский выглядят одинаково (Orbitron/Rajdhani кириллицу не
    // имеют — отсюда был разнобой). Orbitron остаётся только для латинского
    // лого «VARIOUS VPN».
    return GoogleFonts.exo2TextTheme(base).copyWith(
      titleLarge: GoogleFonts.exo2(
          textStyle: base.titleLarge, fontWeight: FontWeight.w700),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: P.lime,
      onPrimary: Color(0xFF0C1206),
      secondary: P.violet,
      onSecondary: Colors.white,
      surface: P.surface,
      onSurface: P.text,
      error: Color(0xFFE2504A),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: P.bg,
      colorScheme: scheme,
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: P.surfaceHi,
      splashFactory: InkRipple.splashFactory,
      // Единый премиальный стиль всех «всплывашек»: скруглённые углы, мягкая
      // тень, фирменная поверхность и тонкая рамка.
      popupMenuTheme: PopupMenuThemeData(
        color: P.surface,
        elevation: 14,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: P.surfaceHi),
        ),
        textStyle: const TextStyle(color: P.text, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: P.surface,
        elevation: 18,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: P.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: P.surface,
        contentTextStyle: const TextStyle(color: P.text),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(P.surface),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: P.surfaceHi),
          )),
        ),
      ),
      // Плавные переходы между экранами (мягкий fade+slide вместо резкого
      // дефолта) — единый премиальный ритм навигации.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: P.lime,
          brightness: Brightness.light,
        ),
        textTheme: _textTheme(Brightness.light),
      );
}
