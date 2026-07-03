/// Векторный флаг страны по коду (без эмодзи — единый стиль на всех платформах).
library;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class CountryFlag extends StatelessWidget {
  final String countryCode;
  final double width;
  const CountryFlag(this.countryCode, {super.key, this.width = 22});

  @override
  Widget build(BuildContext context) {
    final h = width * 16 / 22;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: width,
        height: h,
        child: CustomPaint(painter: _FlagPainter(countryCode)),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final String cc;
  _FlagPainter(this.cc);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint();
    if (cc == 'FI') {
      // Финляндия — синий крест на белом.
      p.color = const Color(0xFFE9E9E9);
      canvas.drawRect(Offset.zero & size, p);
      p.color = const Color(0xFF1E3A6E);
      canvas.drawRect(Rect.fromLTWH(w * 0.28, 0, w * 0.16, h), p);
      canvas.drawRect(Rect.fromLTWH(0, h * 0.40, w, h * 0.2), p);
    } else {
      // Горизонтальные полосы (DE/NL/US/GB-заглушка/прочее).
      final s = P.flagStripes(cc);
      for (var i = 0; i < 3; i++) {
        p.color = s[i];
        canvas.drawRect(Rect.fromLTWH(0, h / 3 * i, w, h / 3 + 0.5), p);
      }
    }
    // тонкая рамка
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0x2EFFFFFF));
  }

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.cc != cc;
}
