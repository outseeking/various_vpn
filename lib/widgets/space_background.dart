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

  /// Насколько «живее» обычного идёт поле. 1 — спокойный фон, больше —
  /// звёзд больше и летят они чаще. Поднимается на время действий, которые
  /// человек запустил сам: обновления подписки и замера пинга.
  final double intensity;

  const SpaceBackground(
      {super.key, this.animate = true, this.intensity = 1});

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

  Duration _lastPaint = Duration.zero;

  void _tick(Duration now) {
    if (_lastPaint != Duration.zero && (now - _lastPaint).inMilliseconds < 33) {
      return; // ~30 fps троттлинг
    }
    _lastPaint = now;
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
          painter: _SpacePainter(_t,
              animate: widget.animate, intensity: widget.intensity),
        ),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final ValueNotifier<double> t;
  final bool animate;
  final double intensity;
  _SpacePainter(this.t, {required this.animate, this.intensity = 1})
      : super(repaint: t);

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
  void _stars(Canvas canvas, Size size, double time, double minY, double maxY) {
    // При повышенной интенсивности звёзд ощутимо больше, но не «каша»:
    // потолок держим в разумных пределах.
    final n = (34 * intensity).round().clamp(34, 90);
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
    const base = [
      [3.5, 0.0, 0.10, 0.15, 0.40],
      [4.5, 1.6, 0.58, 0.35, 0.34],
      [6.0, 3.4, 0.30, 0.60, 0.30],
    ];
    // Дополнительные дорожки включаются только на повышенной интенсивности —
    // в покое небо остаётся спокойным.
    const extra = [
      [2.8, 0.9, 0.74, 0.22, 0.32],
      [3.2, 2.3, 0.18, 0.48, 0.36],
      [3.9, 0.4, 0.46, 0.72, 0.28],
    ];
    final channels = intensity > 1.3 ? [...base, ...extra] : base;
    const travel = 2.4; // с — дольше летит → плавнее (было 1.2)
    for (final c in channels) {
      final local = (time + c[1]) % c[0];
      if (local > travel) continue;
      final lin = (local / travel).clamp(0.0, 1.0);
      // smoothstep-разгон/торможение — движение мягкое, без рывков на старте/финише
      final p = lin * lin * (3 - 2 * lin);
      final sx = size.width * c[2];
      final sy = minY + band * c[3];
      final dx = size.width * c[4], dy = size.width * c[4] * 0.5;
      final hx = sx + dx * p, hy = sy + dy * p;
      final tp = (p - 0.14).clamp(0.0, 1.0);
      final tx = sx + dx * tp, ty = sy + dy * tp;
      // мягкое появление и угасание синусом — не мигает на концах трека
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0);
      // хвост
      canvas.drawLine(
        Offset(tx, ty),
        Offset(hx, hy),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(tx, ty),
            Offset(hx, hy),
            [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.9 * fade)
            ],
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
      canvas.drawCircle(Offset(hx, hy), 2.6,
          Paint()..color = Colors.white.withValues(alpha: fade));
    }
  }

  @override
  bool shouldRepaint(covariant _SpacePainter old) => true;
}
