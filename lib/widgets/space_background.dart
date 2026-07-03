/// Полноэкранный космический фон главного экрана: звёздное поле (мерцает),
/// далёкие планеты в пустых зонах и изредка — падающие звёзды. Рисуется НА ВЕСЬ
/// экран (в отличие от глобуса, чей холст мал), поэтому заполняет пустоту.
/// Уважает флаг анимаций: при выключении всё замирает.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_palette.dart';

class SpaceBackground extends StatefulWidget {
  final bool animate;
  const SpaceBackground({super.key, this.animate = true});

  @override
  State<SpaceBackground> createState() => _SpaceBackgroundState();
}

class _SpaceBackgroundState extends State<SpaceBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);
  double _time = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt =
        _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (widget.animate) {
      _time += dt;
      _t.value = _time;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SpacePainter(_t, animate: widget.animate),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final ValueNotifier<double> t;
  final bool animate;
  _SpacePainter(this.t, {required this.animate}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    // Полоса строго вокруг глобуса: выше — шапка, ниже — кнопка подключения.
    final minY = size.height * 0.13;
    final maxY = size.height * 0.43;
    _stars(canvas, size, time, minY, maxY);
    if (animate) _shooting(canvas, size, time, minY, maxY);
  }

  // Звёзды только в полосе вокруг глобуса. Немного, мягко мерцают.
  void _stars(
      Canvas canvas, Size size, double time, double minY, double maxY) {
    const n = 34;
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final h = (i * 2654435761) & 0x7fffffff;
      final x = (h % 1013) / 1013 * size.width;
      final y = minY + ((h ~/ 1013) % 1013) / 1013 * (maxY - minY);
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(time * 1.5 + i * 1.3));
      final rad = 0.6 + (i % 4) * 0.5;
      final blue = i % 6 == 0;
      final base = blue ? const Color(0xFF94A3B8) : Colors.white;
      p.color = base.withValues(alpha: 0.15 + 0.35 * tw);
      canvas.drawCircle(Offset(x, y), rad, p);
    }
  }

  // Падающие звёзды — белые, яркие, в полосе глобуса; три канала, часто.
  void _shooting(
      Canvas canvas, Size size, double time, double minY, double maxY) {
    final band = maxY - minY;
    // период, фаза, startX(доля), startY(доля полосы 0..1), длина(доля ширины)
    const channels = [
      [3.5, 0.0, 0.10, 0.15, 0.40],
      [4.5, 1.6, 0.58, 0.35, 0.34],
      [6.0, 3.4, 0.30, 0.60, 0.30],
    ];
    for (final c in channels) {
      final local = (time + c[1]) % c[0];
      if (local > 1.2) continue;
      final p = (local / 1.2).clamp(0.0, 1.0);
      final sx = size.width * c[2];
      final sy = minY + band * c[3];
      final dx = size.width * c[4], dy = size.width * c[4] * 0.5;
      final hx = sx + dx * p, hy = sy + dy * p;
      final tp = (p - 0.18).clamp(0.0, 1.0);
      final tx = sx + dx * tp, ty = sy + dy * tp;
      final fade = 1 - p;
      // хвост
      canvas.drawLine(
        Offset(tx, ty),
        Offset(hx, hy),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(tx, ty),
            Offset(hx, hy),
            [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9 * fade)],
          )
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
      // яркая головка + мягкое гало
      canvas.drawCircle(
          Offset(hx, hy),
          5,
          Paint()
            ..color = P.limeText.withValues(alpha: 0.5 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(
          Offset(hx, hy), 2.6, Paint()..color = Colors.white.withValues(alpha: fade));
    }
  }

  @override
  bool shouldRepaint(covariant _SpacePainter old) => true;
}
