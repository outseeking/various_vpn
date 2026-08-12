/// Фирменная палитра Various VPN — тёмная OLED-тема с мягкими контрастами.
/// Утверждена владельцем после серии макетов. Лайм + тёмный фиолет, без розового.
library;

import 'package:flutter/material.dart';

class P {
  P._();

  // --- фоны ---
  // Гамма прежняя (глубокий сине-чёрный), но ступени между слоями стали
  // различимее: раньше карточка на фоне почти сливалась, и интерфейс выглядел
  // «плоским пятном». Теперь фон → поверхность → приподнятая поверхность
  // читаются как три уровня глубины.
  static const bg = Color(0xFF04060B); // почти чёрный с синевой
  static const bgGlobe = Color(0xFF070D18); // вода глобуса
  static const surface = Color(0xFF0C1324); // карточки, шторки, диалоги
  static const surfaceUp = Color(0xFF111A2E); // приподнятый слой (меню, поля)
  static const surfaceHi = Color(0x1AFFFFFF); // рамка/разделитель, .10
  static const surfaceLo = Color(0x0AFFFFFF); // мягкая подложка, .04

  // --- акценты ---
  // Лайм стал чище и ярче (было приглушённо-болотное 0xFF7CB10F), фиолет —
  // насыщеннее. Сама пара лайм + фиолет не менялась: это фирменная гамма.
  static const lime = Color(0xFF8FCE1B); // фирменный лайм (фон/градиент)
  static const limeText = Color(0xFFB4E24E); // лайм для мелкого текста, ~13:1
  static const limeDeep = Color(0xFF5E8A0B); // тёмный край градиента, тени
  static const violet = Color(0xFF6B34B8); // насыщенный фиолет (НЕ розовый)
  static const violetSoft = Color(0xFF9A6BE8); // фиолет для текста и иконок
  static const gold = Color(0xFFEFC24A); // жёлтая галочка локации

  // --- семантика состояний (не «просто цвета», а смысл) ---
  static const success = Color(0xFF57DB77);
  static const danger = Color(0xFFE85C55);
  static const warn = gold;

  /// Текст на лаймовой заливке. Почти чёрный с зелёным подтоном — контраст к
  /// лайму ~9:1, глазу мягче, чем чистый чёрный.
  static const onLime = Color(0xFF0A1004);

  /// Второстепенный текст на лаймовой заливке (подпись под заголовком кнопки).
  static const onLimeDim = Color(0xCC0A1004);

  /// Полупрозрачная плашка на лаймовой заливке (подложка иконки в кнопке).
  static const onLimeGhost = Color(0x260A1004);

  // --- текст ---
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xB3FFFFFF); // 70%
  static const textFaint = Color(0x73FFFFFF); // 45%

  // --- суша/сетка глобуса ---
  static const land = Color(0xFF16243D);
  static const landStroke = Color(0xFF243A5C);
  static const graticule = Color(0x1A789BC8);

  /// Главный фирменный градиент (кнопка, кольцо, акценты). Три остановки вместо
  /// двух: прямой переход лайм→фиолет проходил через грязно-оливковую середину.
  /// Промежуточный тёплый лайм убирает эту «грязь» и делает переход дороже.
  static const grad = LinearGradient(
    begin: Alignment(-0.8, -0.6),
    end: Alignment(0.8, 0.6),
    colors: [lime, Color(0xFF6FA82A), violet],
    stops: [0.0, 0.42, 1.0],
  );

  /// Мягкая подложка карточек: почти невидимый уклон к фиолету. Нужна, чтобы
  /// крупные поверхности не выглядели «залитым серым прямоугольником».
  static const cardGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x12FFFFFF), Color(0x06FFFFFF)],
  );

  /// Цвет качества по пингу (зелёный/жёлтый/красный). -1 = не измерян (серый).
  /// Цвет кружка по пингу. TCP и TLS («via Proxy») меряют по-разному: TLS
  /// включает рукопожатие и в ~2 раза выше, поэтому у него свои диапазоны.
  static Color pingColor(int ms, {bool proxy = false}) {
    if (ms < 0) return const Color(0xFF4B5563);
    final good = proxy ? 200 : 80;
    final mid = proxy ? 380 : 160;
    if (ms < good) return success; // отлично
    if (ms < mid) return warn; // средне
    return danger; // плохо
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
