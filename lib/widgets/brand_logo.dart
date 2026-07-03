/// Фирменный логотип Various VPN: щит (безопасность) с молнией (скорость) и
/// нейро-узлами на фоне (ИИ), в градиенте лайм→фиолет. Векторный, масштабируется.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // щит
    final shield = Path()
      ..moveTo(w * 0.5, h * 0.06)
      ..lineTo(w * 0.9, h * 0.22)
      ..lineTo(w * 0.9, h * 0.55)
      ..cubicTo(w * 0.9, h * 0.78, w * 0.72, h * 0.9, w * 0.5, h * 0.96)
      ..cubicTo(w * 0.28, h * 0.9, w * 0.1, h * 0.78, w * 0.1, h * 0.55)
      ..lineTo(w * 0.1, h * 0.22)
      ..close();

    // заливка щита градиентом лайм→фиолет
    canvas.drawPath(shield, Paint()..shader = P.grad.createShader(rect));

    canvas.save();
    canvas.clipPath(shield);

    // нейро-узлы (ИИ) — тонкие линии + точки, приглушённо
    final cx = w * 0.5, cy = h * 0.5;
    List<Offset> n(List<List<double>> pts) =>
        pts.map((p) => Offset(cx + p[0] * w, cy + p[1] * h)).toList();
    final nodes = n([
      [-0.20, -0.08], [0.17, -0.13], [0.24, 0.10],
      [-0.11, 0.17], [0.10, 0.27], [-0.24, 0.12], [0.02, -0.26],
    ]);
    final edges = [
      [6, 0], [6, 1], [0, 1], [1, 2], [2, 4], [0, 3], [3, 5], [3, 4]
    ];
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008
      ..color = Colors.white.withValues(alpha: 0.22);
    for (final e in edges) {
      canvas.drawLine(nodes[e[0]], nodes[e[1]], line);
    }
    for (final node in nodes) {
      canvas.drawCircle(
          node, w * 0.018, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }

    // молния (скорость) — бело-жёлтая с градиентом
    final bx = cx, by = cy;
    Offset b(double dx, double dy) => Offset(bx + dx * w, by + dy * h);
    final bolt = Path()
      ..moveTo(b(-0.04, -0.30).dx, b(-0.04, -0.30).dy)
      ..lineTo(b(0.18, -0.30).dx, b(0.18, -0.30).dy)
      ..lineTo(b(0.05, -0.04).dx, b(0.05, -0.04).dy)
      ..lineTo(b(0.20, -0.04).dx, b(0.20, -0.04).dy)
      ..lineTo(b(-0.10, 0.36).dx, b(-0.10, 0.36).dy)
      ..lineTo(b(0.01, 0.05).dx, b(0.01, 0.05).dy)
      ..lineTo(b(-0.16, 0.05).dx, b(-0.16, 0.05).dy)
      ..close();
    canvas.drawPath(
        bolt,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF5CD78)],
          ).createShader(rect));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Анимированная версия логотипа для сплеша (кольца раскручиваются, появление).
class AnimatedBrandLogo extends StatefulWidget {
  final double size;
  const AnimatedBrandLogo({super.key, this.size = 120});

  @override
  State<AnimatedBrandLogo> createState() => _AnimatedBrandLogoState();
}

class _AnimatedBrandLogoState extends State<AnimatedBrandLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value * 2 * math.pi;
        return SizedBox(
          width: widget.size * 1.5,
          height: widget.size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: t,
                child: Container(
                  width: widget.size * 1.45,
                  height: widget.size * 1.45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: P.lime.withValues(alpha: 0.25), width: 1.5),
                  ),
                ),
              ),
              Transform.rotate(
                angle: -t * 0.6,
                child: Container(
                  width: widget.size * 1.2,
                  height: widget.size * 1.2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: P.violet.withValues(alpha: 0.35), width: 1),
                  ),
                ),
              ),
              BrandLogo(size: widget.size),
            ],
          ),
        );
      },
    );
  }
}
