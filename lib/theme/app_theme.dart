/// Тема Various VPN. Тёмная — основная (бренд), светлая — на всякий случай
/// (система может попросить).
///
/// Шрифт один на всё приложение и задаётся ключом (см. app_fonts.dart). Важно:
/// стили, которые тема отдаёт компонентам целиком — меню, диалоги, всплывающие
/// сообщения, — обязаны строиться через [_f]. TextStyle без fontFamily такой
/// компонент не домешивает к базовому, а подменяет им стандартный, и текст
/// уезжает на системную гарнитуру.
library;

import 'package:flutter/material.dart';

import 'app_fonts.dart';

import 'app_palette.dart';
import 'motion.dart';

class AppTheme {
  /// Стиль выбранным шрифтом. Через него — ВСЁ, что тема отдаёт компонентам.
  static TextStyle _f(String fontKey, TextStyle style) =>
      AppFonts.byKey(fontKey).style(style);

  static TextTheme _textTheme(Brightness b, String fontKey) {
    final base = b == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;
    // Шрифт выбирает человек в настройках (Настройки → Шрифт). Все варианты с
    // полной кириллицей, поэтому русский и английский выглядят одинаково.
    // Orbitron остаётся только на латинском лого «VARIOUS VPN».
    final font = AppFonts.byKey(fontKey);
    return font.theme(base).copyWith(
      titleLarge: font.style(base.titleLarge ?? const TextStyle())
          .copyWith(fontWeight: FontWeight.w800),
    );
  }

  static ThemeData dark({String fontKey = AppFonts.defaultKey}) {
    const scheme = ColorScheme.dark(
      primary: P.lime,
      onPrimary: P.onLime,
      secondary: P.violet,
      onSecondary: Colors.white,
      surface: P.surface,
      onSurface: P.text,
      error: P.danger,
      surfaceContainerHighest: P.surfaceUp,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: P.bg,
      colorScheme: scheme,
      textTheme: _textTheme(Brightness.dark, fontKey),
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
        textStyle: _f(fontKey, const TextStyle(color: P.text, fontSize: 14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: P.surface,
        elevation: 18,
        // Затемнение фона сильнее дефолтного: диалог должен читаться как
        // отдельный слой, а не как ещё одна карточка поверх экрана.
        barrierColor: const Color(0x99000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: P.surfaceHi),
        ),
        titleTextStyle: _f(
            fontKey,
            const TextStyle(
                color: P.text, fontSize: 18, fontWeight: FontWeight.w800)),
        contentTextStyle:
            _f(fontKey, const TextStyle(
                color: P.textDim, fontSize: 14, height: 1.45)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: P.surface,
        showDragHandle: true,
        dragHandleColor: P.surfaceHi,
        modalBarrierColor: Color(0x99000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: P.surface,
        contentTextStyle: _f(fontKey, const TextStyle(color: P.text)),
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
        TargetPlatform.android: AppPageTransitions(),
        TargetPlatform.iOS: AppPageTransitions(),
      }),
      // Тумблеры: лайм в положении «вкл», приглушённая подложка в «выкл».
      // Раньше это был дефолтный сиреневый Material — чужой для бренда.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected)
                ? P.onLime
                : const Color(0xFFB6C2D4)),
        trackColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected)
                ? P.lime
                : const Color(0xFF25304A)),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? P.lime : P.surfaceHi),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: P.lime,
        thumbColor: P.lime,
        inactiveTrackColor: P.surfaceHi,
      ),
      // Поля ввода — единый вид на всех экранах (раньше каждый экран рисовал
      // свою рамку, где-то дефолтную материаловскую).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: P.surfaceUp,
        hintStyle: _f(fontKey, const TextStyle(color: P.textFaint)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: P.surfaceHi),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: P.surfaceHi),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: P.lime.withValues(alpha: 0.7), width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: P.lime,
          foregroundColor: P.onLime,
          minimumSize: const Size(0, 50),
          textStyle: _f(fontKey,
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: P.text,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: P.surfaceHi),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: P.limeText),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: P.lime,
        linearTrackColor: P.surfaceHi,
      ),
    );
  }

  static ThemeData light({String fontKey = AppFonts.defaultKey}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: P.lime,
          brightness: Brightness.light,
        ),
        textTheme: _textTheme(Brightness.light, fontKey),
      );
}
