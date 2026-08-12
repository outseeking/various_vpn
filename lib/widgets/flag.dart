/// Векторные флаги стран. Без эмодзи: на части прошивок (в том числе на EMUI)
/// эмодзи-флаги не отображаются вовсе или показываются как две буквы.
///
/// Раньше настоящий флаг был только у шести стран, а всё остальное — включая
/// Польшу, откуда у нас несколько серверов, — выглядело как серый прямоугольник
/// с кодом «PL». Теперь флаги рисуются по описанию: большинству стран хватает
/// полос, для остальных есть отдельные рисовалки. Текстовый бейдж остаётся
/// только для по-настоящему неизвестного кода.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Как рисуется флаг страны.
enum _Kind {
  /// Горизонтальные полосы сверху вниз.
  horizontal,

  /// Вертикальные полосы слева направо.
  vertical,

  /// Скандинавский крест: фон + цвет креста (+ необязательная окантовка).
  nordic,

  /// Своя рисовалка (США, Британия, Швейцария, Япония…).
  custom,
}

class _Flag {
  final _Kind kind;
  final List<Color> colors;

  /// Окантовка креста у скандинавских флагов (Норвегия, Исландия).
  final Color? outline;
  const _Flag(this.kind, this.colors, {this.outline});
}

// Цвета слегка приглушены под тёмную тему: чистые «флажные» оттенки на
// почти чёрном фоне выглядят кислотно и спорят с фирменным лаймом.
const _white = Color(0xFFECECEC);
const _red = Color(0xFFC8354A);
const _redDark = Color(0xFF9A2030);
const _blue = Color(0xFF1E3A6E);
const _blueBright = Color(0xFF2A5CA8);
const _yellow = Color(0xFFE8C13C);
const _green = Color(0xFF2F9E5E);
const _black = Color(0xFF141414);
const _orange = Color(0xFFE08A3C);

const _flags = <String, _Flag>{
  // --- две горизонтальные полосы ---
  'PL': _Flag(_Kind.horizontal, [_white, _red]),
  'UA': _Flag(_Kind.horizontal, [_blueBright, _yellow]),
  'ID': _Flag(_Kind.horizontal, [_red, _white]),
  'MC': _Flag(_Kind.horizontal, [_red, _white]),
  'SG': _Flag(_Kind.horizontal, [_red, _white]),

  // --- три горизонтальные полосы ---
  'DE': _Flag(_Kind.horizontal, [_black, _red, _yellow]),
  'NL': _Flag(_Kind.horizontal, [_redDark, _white, _blue]),
  'RU': _Flag(_Kind.horizontal, [_white, _blue, _redDark]),
  'AT': _Flag(_Kind.horizontal, [_red, _white, _red]),
  'LV': _Flag(_Kind.horizontal, [Color(0xFF8B2635), _white, Color(0xFF8B2635)]),
  'EE': _Flag(_Kind.horizontal, [_blueBright, _black, _white]),
  'LT': _Flag(_Kind.horizontal, [_yellow, _green, _red]),
  'HU': _Flag(_Kind.horizontal, [_red, _white, _green]),
  'BG': _Flag(_Kind.horizontal, [_white, _green, _red]),
  'LU': _Flag(_Kind.horizontal, [_red, _white, _blueBright]),
  'AM': _Flag(_Kind.horizontal, [_red, _blue, _orange]),
  'ES': _Flag(_Kind.horizontal, [_red, _yellow, _red]),

  // --- вертикальные полосы ---
  'FR': _Flag(_Kind.vertical, [_blue, _white, _redDark]),
  'IT': _Flag(_Kind.vertical, [_green, _white, _red]),
  'IE': _Flag(_Kind.vertical, [_green, _white, _orange]),
  'BE': _Flag(_Kind.vertical, [_black, _yellow, _red]),
  'RO': _Flag(_Kind.vertical, [_blue, _yellow, _red]),
  'MD': _Flag(_Kind.vertical, [_blue, _yellow, _red]),

  // --- скандинавский крест ---
  'FI': _Flag(_Kind.nordic, [_white, _blue]),
  'SE': _Flag(_Kind.nordic, [Color(0xFF1B5EA8), _yellow]),
  'DK': _Flag(_Kind.nordic, [_red, _white]),
  'NO': _Flag(_Kind.nordic, [_red, _blue], outline: _white),
  'IS': _Flag(_Kind.nordic, [_blue, _red], outline: _white),

  // --- со своим рисунком ---
  'US': _Flag(_Kind.custom, []),
  'GB': _Flag(_Kind.custom, []),
  'CH': _Flag(_Kind.custom, []),
  'JP': _Flag(_Kind.custom, []),
  'TR': _Flag(_Kind.custom, []),
  'CZ': _Flag(_Kind.custom, []),
  'PT': _Flag(_Kind.custom, []),
  'CA': _Flag(_Kind.custom, []),
  'KZ': _Flag(_Kind.custom, []),
  'IL': _Flag(_Kind.custom, []),
  'HK': _Flag(_Kind.custom, []),
  'AE': _Flag(_Kind.custom, []),
  'IN': _Flag(_Kind.custom, []),
  // Не страна, но в чужих подписках сплошь и рядом: узлы «Европа» помечают
  // флагом ЕС, и без рисунка вместо флага висел текст «EU».
  'EU': _Flag(_Kind.custom, []),

  // --- дополненный набор: страна не должна оставаться голым кодом ---
  // Горизонтальные полосы.
  'SK': _Flag(_Kind.horizontal, [_white, _blueBright, _red]),
  'SI': _Flag(_Kind.horizontal, [_white, _blueBright, _red]),
  'HR': _Flag(_Kind.horizontal, [_red, _white, _blue]),
  'RS': _Flag(_Kind.horizontal, [_red, _blue, _white]),
  'ME': _Flag(_Kind.horizontal, [_red, _yellow, _red]),
  'BY': _Flag(_Kind.horizontal, [_red, _green]),
  'EG': _Flag(_Kind.horizontal, [_red, _white, _black]),
  'IQ': _Flag(_Kind.horizontal, [_red, _white, _black]),
  'IR': _Flag(_Kind.horizontal, [_green, _white, _red]),
  'BH': _Flag(_Kind.horizontal, [_white, _red]),
  'QA': _Flag(_Kind.horizontal, [_white, Color(0xFF8A1538)]),
  'OM': _Flag(_Kind.horizontal, [_white, _red, _green]),
  'KW': _Flag(_Kind.horizontal, [_green, _white, _red]),
  'AL': _Flag(_Kind.custom, []),
  'MK': _Flag(_Kind.horizontal, [_red, _yellow, _red]),
  'BA': _Flag(_Kind.horizontal, [_blue, _yellow, _blue]),
  'AZ': _Flag(_Kind.horizontal, [_blueBright, _red, _green]),
  'UZ': _Flag(_Kind.horizontal, [_blueBright, _white, _green]),
  'TJ': _Flag(_Kind.horizontal, [_red, _white, _green]),
  'TH': _Flag(_Kind.horizontal, [_red, _white, _blue, _white, _red]),
  'CO': _Flag(_Kind.horizontal, [_yellow, _blue, _red]),
  'AR': _Flag(_Kind.horizontal, [Color(0xFF74ACDF), _white, Color(0xFF74ACDF)]),
  'ZA': _Flag(_Kind.horizontal, [_red, _white, _blue]),
  'KE': _Flag(_Kind.horizontal, [_black, _red, _green]),
  'GE': _Flag(_Kind.custom, []),

  // Вертикальные полосы.
  'PE': _Flag(_Kind.vertical, [_red, _white, _red]),
  'NG': _Flag(_Kind.vertical, [_green, _white, _green]),
  'MX': _Flag(_Kind.vertical, [_green, _white, _red]),
  'CY': _Flag(_Kind.horizontal, [_white, Color(0xFFD4A24A), _white]),
  'MT': _Flag(_Kind.vertical, [_white, _red]),
  'PK': _Flag(_Kind.vertical, [_white, _green]),
  'BD': _Flag(_Kind.custom, []),
  'MA': _Flag(_Kind.custom, []),
  'SA': _Flag(_Kind.custom, []),
  'GR': _Flag(_Kind.custom, []),
  'CN': _Flag(_Kind.custom, []),
  'KR': _Flag(_Kind.custom, []),
  'TW': _Flag(_Kind.custom, []),
  'VN': _Flag(_Kind.custom, []),
  'MY': _Flag(_Kind.custom, []),
  'PH': _Flag(_Kind.custom, []),
  'MN': _Flag(_Kind.custom, []),
  'BR': _Flag(_Kind.custom, []),
  'CL': _Flag(_Kind.custom, []),
  'AU': _Flag(_Kind.custom, []),
  'NZ': _Flag(_Kind.custom, []),
  'KG': _Flag(_Kind.custom, []),
};

class CountryFlag extends StatelessWidget {
  final String countryCode;
  final double width;
  const CountryFlag(this.countryCode, {super.key, this.width = 22});

  bool get _valid2 =>
      countryCode.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(countryCode);

  @override
  Widget build(BuildContext context) {
    final h = width * 16 / 22;
    final cc = countryCode.toUpperCase();
    final flag = _flags[cc];

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: h,
        child: flag != null
            ? CustomPaint(painter: _FlagPainter(cc, flag))
            : _valid2
                // Страна распознана, но флага для неё пока нет — аккуратный
                // бейдж с кодом. Лучше, чем пустой глобус: код хотя бы
                // называет страну.
                ? Container(
                    alignment: Alignment.center,
                    color: const Color(0xFF223049),
                    child: Text(cc,
                        style: TextStyle(
                            color: const Color(0xFFCFE0FF),
                            fontSize: h * 0.62,
                            fontWeight: FontWeight.w700,
                            height: 1)),
                  )
                : const Icon(Icons.public, size: 14, color: Color(0x73FFFFFF)),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final String cc;
  final _Flag flag;
  _FlagPainter(this.cc, this.flag);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint();

    void fill(Color c) {
      p.color = c;
      canvas.drawRect(Offset.zero & size, p);
    }

    void bands(List<Color> cs, {required bool vertical}) {
      final n = cs.length;
      for (var i = 0; i < n; i++) {
        p.color = cs[i];
        // +0.5 к размеру — чтобы между полосами не просвечивал фон.
        canvas.drawRect(
          vertical
              ? Rect.fromLTWH(w / n * i, 0, w / n + 0.5, h)
              : Rect.fromLTWH(0, h / n * i, w, h / n + 0.5),
          p,
        );
      }
    }

    /// Скандинавский крест: вертикаль смещена к древку.
    void nordic(Color bg, Color cross, {Color? outline}) {
      fill(bg);
      final vx = w * 0.30, vw = w * 0.17, hy = h * 0.40, hh = h * 0.20;
      if (outline != null) {
        p.color = outline;
        canvas.drawRect(
            Rect.fromLTWH(vx - vw * 0.45, 0, vw * 1.9, h), p);
        canvas.drawRect(
            Rect.fromLTWH(0, hy - hh * 0.45, w, hh * 1.9), p);
      }
      p.color = cross;
      canvas.drawRect(Rect.fromLTWH(vx, 0, vw, h), p);
      canvas.drawRect(Rect.fromLTWH(0, hy, w, hh), p);
    }

    switch (flag.kind) {
      case _Kind.horizontal:
        bands(flag.colors, vertical: false);
      case _Kind.vertical:
        bands(flag.colors, vertical: true);
      case _Kind.nordic:
        nordic(flag.colors[0], flag.colors[1], outline: flag.outline);
      case _Kind.custom:
        _custom(canvas, size, p, fill, bands, nordic);
    }

    // Тонкая рамка: на светлых флагах (Польша, Япония) без неё не видно края.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0x3DFFFFFF));
  }

  void _custom(
    Canvas canvas,
    Size size,
    Paint p,
    void Function(Color) fill,
    void Function(List<Color>, {required bool vertical}) bands,
    void Function(Color, Color, {Color? outline}) nordic,
  ) {
    final w = size.width, h = size.height;
    switch (cc) {
      case 'US':
        // Полосы + синий кантон. Звёзды на 22px не читаются — точки.
        fill(_white);
        p.color = _redDark;
        for (var i = 0; i < 7; i++) {
          canvas.drawRect(Rect.fromLTWH(0, h / 13 * i * 2, w, h / 13 + 0.5), p);
        }
        p.color = const Color(0xFF2A3B6E);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.42, h * 7 / 13), p);
        p.color = _white;
        for (var r = 0; r < 3; r++) {
          for (var c = 0; c < 4; c++) {
            canvas.drawCircle(
                Offset(w * (0.07 + c * 0.095), h * (0.09 + r * 0.13)),
                w * 0.016,
                p);
          }
        }
      case 'EU':
        // Синее полотно и кольцо из двенадцати звёзд. На 22px звезда в пиксель
        // не читается — рисуем точки, силуэт кольца узнаётся именно им.
        fill(const Color(0xFF1B3A8C));
        p.color = _yellow;
        for (var i = 0; i < 12; i++) {
          final a = math.pi * 2 * i / 12 - math.pi / 2;
          canvas.drawCircle(
            Offset(w / 2 + math.cos(a) * w * 0.19,
                h / 2 + math.sin(a) * h * 0.26),
            w * 0.028,
            p,
          );
        }
      case 'GB':
        // Union Jack: диагонали, затем прямой крест поверх.
        fill(const Color(0xFF1E3A6E));
        p
          ..color = _white
          ..strokeWidth = h * 0.20
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(0, h), p);
        p
          ..color = _redDark
          ..strokeWidth = h * 0.09;
        canvas.drawLine(Offset.zero, Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(0, h), p);
        p.style = PaintingStyle.fill;
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.38, 0, w * 0.24, h), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.33, w, h * 0.34), p);
        p.color = _redDark;
        canvas.drawRect(Rect.fromLTWH(w * 0.43, 0, w * 0.14, h), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.40, w, h * 0.20), p);
      case 'CH':
        fill(_red);
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.20, w * 0.16, h * 0.60), p);
        canvas.drawRect(Rect.fromLTWH(w * 0.25, h * 0.40, w * 0.50, h * 0.20), p);
      case 'JP':
        fill(_white);
        p.color = const Color(0xFFC4344A);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.30, p);
      case 'TR':
        fill(const Color(0xFFC4344A));
        p.color = _white;
        canvas.drawCircle(Offset(w * 0.36, h / 2), h * 0.22, p);
        p.color = const Color(0xFFC4344A);
        canvas.drawCircle(Offset(w * 0.42, h / 2), h * 0.18, p);
        p.color = _white;
        _star(canvas, p, Offset(w * 0.60, h / 2), h * 0.13);
      case 'CZ':
        // Две полосы + синий клин от древка.
        bands(const [_white, _redDark], vertical: false);
        p.color = const Color(0xFF1E3A6E);
        canvas.drawPath(
            Path()
              ..moveTo(0, 0)
              ..lineTo(w * 0.46, h / 2)
              ..lineTo(0, h)
              ..close(),
            p);
      case 'PT':
        p.color = const Color(0xFF1F6B45);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.40, h), p);
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(w * 0.40, 0, w * 0.60, h), p);
        p.color = _yellow;
        canvas.drawCircle(Offset(w * 0.40, h / 2), h * 0.20, p);
      case 'CA':
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.25, h), p);
        canvas.drawRect(Rect.fromLTWH(w * 0.75, 0, w * 0.25, h), p);
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.25, 0, w * 0.50, h), p);
        // Кленовый лист целиком на такой высоте нечитаем, но силуэт с тремя
        // зубцами и ножкой уже узнаётся — в отличие от ромба, который читался
        // как масть игральной карты.
        p.color = const Color(0xFFC4344A);
        canvas.drawPath(
            Path()
              ..moveTo(w / 2, h * 0.20)
              ..lineTo(w * 0.565, h * 0.40)
              ..lineTo(w * 0.625, h * 0.36)
              ..lineTo(w * 0.60, h * 0.56)
              ..lineTo(w * 0.66, h * 0.54)
              ..lineTo(w * 0.53, h * 0.66)
              ..lineTo(w * 0.545, h * 0.82)
              ..lineTo(w * 0.455, h * 0.82)
              ..lineTo(w * 0.47, h * 0.66)
              ..lineTo(w * 0.34, h * 0.54)
              ..lineTo(w * 0.40, h * 0.56)
              ..lineTo(w * 0.375, h * 0.36)
              ..lineTo(w * 0.435, h * 0.40)
              ..close(),
            p);
      case 'KZ':
        fill(const Color(0xFF1A9FB0));
        p.color = _yellow;
        canvas.drawCircle(Offset(w / 2, h * 0.46), h * 0.18, p);
      case 'IL':
        fill(_white);
        p.color = const Color(0xFF2A5CA8);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.10, w, h * 0.12), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.12), p);
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.06;
        _triangle(canvas, p, Offset(w / 2, h / 2), h * 0.22, false);
        _triangle(canvas, p, Offset(w / 2, h / 2), h * 0.22, true);
        p.style = PaintingStyle.fill;
      case 'HK':
        fill(const Color(0xFFC4344A));
        p.color = _white;
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.22, p);
        p.color = const Color(0xFFC4344A);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.10, p);
      case 'AE':
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.28, h), p);
        bandsRight(canvas, p, w, h);
      case 'CN':
        fill(const Color(0xFFC4344A));
        p.color = _yellow;
        _star(canvas, p, Offset(w * 0.20, h * 0.30), h * 0.16);
        for (var i = 0; i < 4; i++) {
          _star(canvas, p,
              Offset(w * 0.36, h * (0.14 + i * 0.14)), h * 0.055);
        }
      case 'KR':
        fill(_white);
        p.color = const Color(0xFFC4344A);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.22, p);
        p.color = const Color(0xFF2A5CA8);
        canvas.drawArc(
            Rect.fromCircle(center: Offset(w / 2, h / 2), radius: h * 0.22),
            0, math.pi, true, p);
        p.color = _black;
        canvas.drawRect(Rect.fromLTWH(w * 0.10, h * 0.16, w * 0.10, h * 0.05), p);
        canvas.drawRect(Rect.fromLTWH(w * 0.80, h * 0.79, w * 0.10, h * 0.05), p);
      case 'TW':
        fill(const Color(0xFFC4344A));
        p.color = const Color(0xFF2A3B8F);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.5, h * 0.5), p);
        p.color = _white;
        _star(canvas, p, Offset(w * 0.25, h * 0.25), h * 0.14);
      case 'VN':
        fill(const Color(0xFFC4344A));
        p.color = _yellow;
        _star(canvas, p, Offset(w / 2, h / 2), h * 0.26);
      case 'MY':
        for (var i = 0; i < 7; i++) {
          p.color = i.isEven ? const Color(0xFFC4344A) : _white;
          canvas.drawRect(Rect.fromLTWH(0, h / 7 * i, w, h / 7 + 0.5), p);
        }
        p.color = const Color(0xFF2A3B8F);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.5, h * 4 / 7), p);
        p.color = _yellow;
        _star(canvas, p, Offset(w * 0.34, h * 0.28), h * 0.10);
      case 'PH':
        p.color = const Color(0xFF2A5CA8);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 2), p);
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(0, h / 2, w, h / 2), p);
        p.color = _white;
        canvas.drawPath(
            Path()
              ..moveTo(0, 0)
              ..lineTo(w * 0.44, h / 2)
              ..lineTo(0, h)
              ..close(),
            p);
        p.color = _yellow;
        _star(canvas, p, Offset(w * 0.14, h / 2), h * 0.11);
      case 'MN':
        bands(const [_red, Color(0xFF2A5CA8), _red], vertical: true);
        p.color = _yellow;
        canvas.drawRect(Rect.fromLTWH(w * 0.09, h * 0.30, w * 0.05, h * 0.40), p);
      case 'BR':
        fill(const Color(0xFF1F9B4B));
        p.color = _yellow;
        canvas.drawPath(
            Path()
              ..moveTo(w / 2, h * 0.14)
              ..lineTo(w * 0.86, h / 2)
              ..lineTo(w / 2, h * 0.86)
              ..lineTo(w * 0.14, h / 2)
              ..close(),
            p);
        p.color = const Color(0xFF2A3B8F);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.17, p);
      case 'CL':
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 2), p);
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(0, h / 2, w, h / 2), p);
        p.color = const Color(0xFF2A3B8F);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.34, h / 2), p);
        p.color = _white;
        _star(canvas, p, Offset(w * 0.17, h * 0.25), h * 0.13);
      case 'AU':
      case 'NZ':
        fill(const Color(0xFF1E3A6E));
        // Уголок с британским крестом — узнаваемая часть обоих флагов.
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.15, 0, w * 0.07, h / 2), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.20, w / 2, h * 0.09), p);
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(w * 0.17, 0, w * 0.035, h / 2), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.225, w / 2, h * 0.04), p);
        p.color = cc == 'NZ' ? const Color(0xFFC4344A) : _white;
        _star(canvas, p, Offset(w * 0.74, h * 0.34), h * 0.09);
        _star(canvas, p, Offset(w * 0.82, h * 0.62), h * 0.07);
        _star(canvas, p, Offset(w * 0.66, h * 0.72), h * 0.07);
      case 'GR':
        for (var i = 0; i < 9; i++) {
          p.color = i.isEven ? const Color(0xFF2A5CA8) : _white;
          canvas.drawRect(Rect.fromLTWH(0, h / 9 * i, w, h / 9 + 0.5), p);
        }
        p.color = const Color(0xFF2A5CA8);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.30, h * 5 / 9), p);
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.12, 0, w * 0.06, h * 5 / 9), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.24, w * 0.30, h * 0.06), p);
      case 'SA':
        fill(const Color(0xFF1F7A4A));
        p.color = _white;
        canvas.drawRect(Rect.fromLTWH(w * 0.18, h * 0.42, w * 0.64, h * 0.07), p);
        canvas.drawRect(Rect.fromLTWH(w * 0.22, h * 0.60, w * 0.40, h * 0.05), p);
      case 'MA':
        fill(const Color(0xFFC4344A));
        p
          ..color = const Color(0xFF1F7A4A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        _star(canvas, p, Offset(w / 2, h / 2), h * 0.24);
        p.style = PaintingStyle.fill;
      case 'BD':
        fill(const Color(0xFF1F7A4A));
        p.color = const Color(0xFFC4344A);
        canvas.drawCircle(Offset(w * 0.44, h / 2), h * 0.26, p);
      case 'AL':
        fill(const Color(0xFFC4344A));
        // Двуглавый орёл в 22 пикселя не нарисовать — тёмное пятно по центру
        // хотя бы отличает Албанию от простого красного полотна.
        p.color = const Color(0xFF241014);
        canvas.drawPath(
            Path()
              ..moveTo(w * 0.30, h * 0.36)
              ..lineTo(w / 2, h * 0.50)
              ..lineTo(w * 0.70, h * 0.36)
              ..lineTo(w * 0.62, h * 0.66)
              ..lineTo(w * 0.38, h * 0.66)
              ..close(),
            p);
      case 'KG':
        fill(const Color(0xFFC4344A));
        p.color = _yellow;
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.20, p);
      case 'GE':
        fill(_white);
        p.color = const Color(0xFFC4344A);
        canvas.drawRect(Rect.fromLTWH(w * 0.42, 0, w * 0.16, h), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.42, w, h * 0.16), p);
      case 'IN':
        bands(const [_orange, _white, _green], vertical: false);
        p
          ..color = const Color(0xFF2A5CA8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.13, p);
        p.style = PaintingStyle.fill;
    }
  }

  /// Три полосы правее древка (ОАЭ).
  void bandsRight(Canvas canvas, Paint p, double w, double h) {
    const cs = [_green, _white, _black];
    for (var i = 0; i < 3; i++) {
      p.color = cs[i];
      canvas.drawRect(
          Rect.fromLTWH(w * 0.28, h / 3 * i, w * 0.72, h / 3 + 0.5), p);
    }
  }

  void _star(Canvas canvas, Paint p, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.42;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  void _triangle(Canvas canvas, Paint p, Offset c, double r, bool down) {
    final path = Path();
    for (var i = 0; i < 3; i++) {
      final a = (down ? math.pi / 2 : -math.pi / 2) + i * 2 * math.pi / 3;
      final pt = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p);
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.cc != cc;
}
