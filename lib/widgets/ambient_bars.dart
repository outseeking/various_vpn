/// Декоративный фон: мягкие размытые диагональные «полоски» лайм/фиолет в
/// пустых зонах экрана. В покое едва заметны; при подключении плавно
/// разгораются ярче и медленно затухают обратно — оживляют главный экран.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_palette.dart';

class AmbientBars extends StatefulWidget {
  final bool connected;
  final bool animate;
  const AmbientBars({super.key, required this.connected, this.animate = true});

  @override
  State<AmbientBars> createState() => _AmbientBarsState();
}

class _AmbientBarsState extends State<AmbientBars>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);

  // яркость: плавно тянется к целевой (1 при подключении, 0 в покое) + при
  // свежем подключении кратковременная вспышка сверху 1.0.
  double _bright = 0;
  double _flash = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(AmbientBars old) {
    super.didUpdateWidget(old);
    if (widget.connected && !old.connected) _flash = 1.0;
  }

  void _tick(Duration now) {
    final dt =
        _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!widget.animate) return; // флаг анимаций выключен — полоски замирают
    final target = widget.connected ? 1.0 : 0.0;
    _bright += (target - _bright) * (dt * 1.6).clamp(0, 1);
    if (_flash > 0) _flash = (_flash - dt * 0.5).clamp(0, 1);
    _t.value += dt;
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
          painter: _BarsPainter(_t, () => _bright, () => _flash),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final ValueNotifier<double> t;
  final double Function() bright;
  final double Function() flash;
  _BarsPainter(this.t, this.bright, this.flash) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final b = bright();
    final fl = flash();
    // базовая (очень тихая) видимость + добавка от подключения
    const baseA = 0.05;
    final onA = 0.22 * b + 0.25 * fl;

    // полоски как в первой версии — ПАРАЛЛЕЛЬНЫЕ друг другу (единый наклон),
    // разной длины/фазы. При подключении красиво переливаются (бегущая волна
    // яркости слева направо).
    const angle = -0.6; // общий наклон для всех
    final bars = <_Bar>[
      _Bar(0.14, 0.30, 0.58, P.violet, 0.0, angle, 0.050),
      _Bar(0.34, 0.62, 0.50, P.lime, 0.6, angle, 0.044),
      _Bar(0.55, 0.24, 0.44, P.limeText, 1.2, angle, 0.038),
      _Bar(0.74, 0.66, 0.60, P.violet, 1.8, angle, 0.048),
      _Bar(0.90, 0.34, 0.46, P.lime, 2.4, angle, 0.040),
    ];

    for (final bar in bars) {
      // перелив: бегущая волна (зависит и от позиции x, и от времени)
      final shimmer = 0.6 + 0.4 * math.sin(time * 1.1 + bar.phase - bar.x * 3);
      final alpha = (baseA + onA * shimmer).clamp(0.0, 0.55);
      final cx = size.width * bar.x;
      final cy = size.height * bar.y;
      final len = size.height * bar.len;
      final w = size.width * bar.width;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(bar.angle);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: len),
        Radius.circular(w),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = bar.color.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

class _Bar {
  final double x, y, len;
  final Color color;
  final double phase;
  final double angle;
  final double width;
  _Bar(this.x, this.y, this.len, this.color, this.phase, this.angle, this.width);
}
