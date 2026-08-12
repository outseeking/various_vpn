/// Шрифты приложения: список кандидатов и текущий выбор.
///
/// Вынесено отдельно, потому что шрифт выбирает человек в настройках, а не
/// разработчик один раз. Все варианты — с полной кириллицей: иначе русский и
/// английский выглядели бы разными шрифтами.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppFont {
  /// Ключ для хранилища. Менять нельзя — по нему восстанавливается выбор.
  final String key;

  /// Имя, как его видит человек.
  final String title;

  /// Готовый стиль поверх базового.
  final TextStyle Function(TextStyle base) style;

  /// Тема целиком — из неё строится оформление приложения.
  final TextTheme Function(TextTheme base) theme;

  const AppFont({
    required this.key,
    required this.title,
    required this.style,
    required this.theme,
  });
}

class AppFonts {
  AppFonts._();

  static final all = <AppFont>[
    AppFont(
      key: 'manrope',
      title: 'Manrope — мягкий и современный',
      style: (b) => GoogleFonts.manrope(textStyle: b),
      theme: GoogleFonts.manropeTextTheme,
    ),
    AppFont(
      key: 'onest',
      title: 'Onest — тёплый, рисовался под кириллицу',
      style: (b) => GoogleFonts.onest(textStyle: b),
      theme: GoogleFonts.onestTextTheme,
    ),
    AppFont(
      key: 'golos',
      title: 'Golos Text — плотный, для интерфейсов',
      style: (b) => GoogleFonts.golosText(textStyle: b),
      theme: GoogleFonts.golosTextTextTheme,
    ),
    AppFont(
      key: 'inter',
      title: 'Inter — нейтральный стандарт',
      style: (b) => GoogleFonts.inter(textStyle: b),
      theme: GoogleFonts.interTextTheme,
    ),
    AppFont(
      key: 'nunito',
      title: 'Nunito Sans — круглый и дружелюбный',
      style: (b) => GoogleFonts.nunitoSans(textStyle: b),
      theme: GoogleFonts.nunitoSansTextTheme,
    ),
    AppFont(
      key: 'exo2',
      title: 'Exo 2 — техно, угловатый',
      style: (b) => GoogleFonts.exo2(textStyle: b),
      theme: GoogleFonts.exo2TextTheme,
    ),
  ];

  static const defaultKey = 'exo2';

  static AppFont byKey(String key) =>
      all.firstWhere((f) => f.key == key, orElse: () => all.first);
}
