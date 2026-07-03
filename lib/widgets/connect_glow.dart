/// Свечение по краям экрана при подключении к VPN.
///
/// При переходе в «подключено» по периметру экрана вспыхивает лаймово-фиолетовое
/// свечение (внутренняя виньетка) и плавно затухает за ~2.5 сек до нуля —
/// приятный визуальный сигнал успешного подключения. Не перехватывает касания.
library;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class ConnectGlow extends StatefulWidget {
  final bool connected;
  const ConnectGlow({super.key, required this.connected});

  @override
  State<ConnectGlow> createState() => _ConnectGlowState();
}

class _ConnectGlowState extends State<ConnectGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );

  @override
  void didUpdateWidget(ConnectGlow old) {
    super.didUpdateWidget(old);
    if (widget.connected && !old.connected) {
      _c.forward(from: 0);
    } else if (!widget.connected && old.connected) {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // яркая вспышка в начале (1) → мягкое остаточное свечение (0.18)
          final t = Curves.easeOut.transform(_c.value);
          final intensity = widget.connected ? (1 - t) * 0.82 + 0.18 : 0.0;
          if (intensity <= 0.01) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _GlowPainter(intensity: intensity),
          );
        },
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final double intensity;
  _GlowPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    // Свечение только СВЕРХУ: вертикальный градиент от верхнего края вниз,
    // затухающий примерно к трети экрана. Внизу (у списка серверов) — чисто.
    final h = size.height * 0.34;
    final rect = Rect.fromLTWH(0, 0, size.width, h);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          P.violet.withValues(alpha: 0.55 * intensity),
          P.lime.withValues(alpha: 0.28 * intensity),
          P.lime.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.intensity != intensity;
}
