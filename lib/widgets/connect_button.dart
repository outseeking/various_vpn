/// Большая круглая кнопка подключения с переливающимся кольцом «как Моя волна».
///
/// Поведение: при подключении кольцо бурлит ярко (быстрое вращение градиента +
/// сильная пульсация), за ~4 сек затихает в спокойный стабильный режим (но не
/// до конца) — сигнал, что соединение живо. В отключённом виде кольца нет.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class ConnectButton extends StatefulWidget {
  final bool connected;
  final bool busy;
  final VoidCallback onTap;
  final String label; // «Защищено» / «Отключено» / «Подключение…»
  final bool animate; // false в Lite-режиме — кольцо статичное

  const ConnectButton({
    super.key,
    required this.connected,
    required this.busy,
    required this.onTap,
    required this.label,
    this.animate = true,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  // «энергия» кольца: 1 при свежем подключении, спадает к ~0.35 (стабильно).
  late final AnimationController _energy = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  // мягкое затухание энергии (без линейного «спада рывком»)
  late final Animation<double> _energyCurve =
      CurvedAnimation(parent: _energy, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _syncAnim();
  }

  // Запускает/останавливает бесконечные анимации кольца по флагу [animate].
  void _syncAnim() {
    if (widget.animate) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _spin.stop();
      _pulse.stop();
    }
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) _syncAnim();
    if (widget.connected && !old.connected) {
      widget.animate ? _energy.forward(from: 0) : _energy.value = 1;
    } else if (!widget.connected && old.connected) {
      _energy.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _energy.dispose();
    super.dispose();
  }

  bool _pressed = false;
  void _setPressed(bool v) {
    if (widget.busy || !widget.animate) return; // в Lite — без анимации нажатия
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        // упругое «вжатие» при нажатии — тактильно и дорого
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: SizedBox(
        width: 168,
        height: 168,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _pulse, _energyCurve]),
          builder: (context, _) {
            // энергия: до окончания контроллера 1→0 (плавно), дальше держим 0.35
            final raw = widget.connected ? (1 - _energyCurve.value) : 0.0;
            final energy = widget.connected ? (0.35 + 0.65 * raw) : 0.0;
            return CustomPaint(
              painter: _RingPainter(
                spin: _spin.value,
                pulse: _pulse.value,
                energy: energy,
                connected: widget.connected,
              ),
              child: Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.3, -0.4),
                      colors: [Color(0xFF131D33), Color(0xFF080E1A)],
                    ),
                    border: Border.fromBorderSide(
                        BorderSide(color: Color(0x335E2C9E))),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.busy)
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: P.limeText),
                        )
                      else
                        TweenAnimationBuilder<Color?>(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          tween: ColorTween(
                              end: widget.connected ? P.limeText : P.textFaint),
                          builder: (_, color, __) => Icon(
                              Icons.power_settings_new_rounded,
                              size: 40,
                              color: color),
                        ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(widget.label,
                            key: ValueKey(widget.label),
                            style: const TextStyle(
                                fontSize: 12, color: P.textDim)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double spin; // 0..1
  final double pulse; // 0..1
  final double energy; // 0..1
  final bool connected;
  _RingPainter({
    required this.spin,
    required this.pulse,
    required this.energy,
    required this.connected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 2 - 24;

    if (connected) {
      // расходящееся кольцо-пульс
      final pr = base + 8 + pulse * 22 * energy;
      canvas.drawCircle(
          c,
          pr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = P.lime.withValues(alpha: (1 - pulse) * 0.6 * energy));

      // переливающееся кольцо (конический градиент лайм↔фиолет)
      final sweep = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(spin * 2 * math.pi),
        colors: const [
          P.lime, P.violet, P.lime, P.violet, P.lime,
        ],
      );
      canvas.drawCircle(
          c,
          base + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 + energy * 6
            ..shader = sweep.createShader(
                Rect.fromCircle(center: c, radius: base + 4))
            ..maskFilter = MaskFilter.blur(
                BlurStyle.normal, 3 + energy * 6));
    }

    // статичный тонкий контур
    canvas.drawCircle(
        c,
        base + 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = connected ? P.lime.withValues(alpha: 0.5) : P.surfaceHi);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}
