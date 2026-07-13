/// Фирменная палитра Various VPN — тёмная OLED-тема с мягкими контрастами.
/// Утверждена владельцем после серии макетов. Лайм + тёмный фиолет, без розового.
library;

import 'package:flutter/material.dart';

class P {
  P._();

  // --- фоны ---
  static const bg = Color(0xFF05070C); // почти чёрный с синевой
  static const bgGlobe = Color(0xFF070D18); // вода глобуса
  static const surface = Color(0xFF0B1120);
  static const surfaceHi = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const surfaceLo = Color(0x08FFFFFF); // rgba(255,255,255,.03)

  // --- акценты ---
  static const lime = Color(0xFF7CB10F); // приглушённый лайм (фон/градиент)
  static const limeText = Color(0xFF9BCB3C); // лайм для мелкого читаемого текста
  static const violet = Color(0xFF5E2C9E); // тёмный фиолет (НЕ розовый)
  static const gold = Color(0xFFE0B53A); // жёлтая галочка локации

  // --- текст ---
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xB3FFFFFF); // 70%
  static const textFaint = Color(0x73FFFFFF); // 45%

  // --- суша/сетка глобуса ---
  static const land = Color(0xFF16243D);
  static const landStroke = Color(0xFF243A5C);
  static const graticule = Color(0x1A789BC8);

  /// Главный фирменный градиент (кнопка, кольцо, акценты).
  static const grad = LinearGradient(
    begin: Alignment(-0.8, -0.6),
    end: Alignment(0.8, 0.6),
    colors: [lime, violet],
  );

  /// Цвет качества по пингу (зелёный/жёлтый/красный). -1 = не измерян (серый).
  /// Цвет кружка по пингу. TCP и TLS («via Proxy») меряют по-разному: TLS
  /// включает рукопожатие и в ~2 раза выше, поэтому у него свои диапазоны.
  static Color pingColor(int ms, {bool proxy = false}) {
    if (ms < 0) return const Color(0xFF4B5563);
    final good = proxy ? 200 : 80;
    final mid = proxy ? 380 : 160;
    if (ms < good) return const Color(0xFF4ED16B); // отлично
    if (ms < mid) return gold; // средне
    return const Color(0xFFE2504A); // плохо
  }

  /// Цвета флага по коду страны (горизонтальные полосы, сверху вниз).
  /// Десатурированы под тёмную тему.
  static List<Color> flagStripes(String cc) => switch (cc) {
        'DE' => const [Color(0xFF111111), Color(0xFFC8102E), Color(0xFFE0B300)],
        'NL' => const [Color(0xFF9A2030), Color(0xFFE9E9E9), Color(0xFF1E3A6E)],
        'RU' => const [Color(0xFFE9E9E9), Color(0xFF1E3A6E), Color(0xFF9A2030)],
        'US' => const [Color(0xFFB22234), Color(0xFFE9E9E9), Color(0xFF3C3B6E)],
        'GB' => const [Color(0xFF1E3A6E), Color(0xFFE9E9E9), Color(0xFF9A2030)],
        _ => const [Color(0xFF334155), Color(0xFF475569), Color(0xFF334155)],
      };
}
