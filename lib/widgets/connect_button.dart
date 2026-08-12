/// Большая круглая кнопка подключения с переливающимся кольцом «как Моя волна».
///
/// Поведение: при подключении кольцо бурлит ярко (быстрое вращение градиента +
/// сильная пульсация), за ~4 сек затихает в спокойный стабильный режим (но не
/// до конца) — сигнал, что соединение живо. В отключённом виде кольца нет.
///
/// Нажатие (переработано под «дорогое» ощущение, как в Happ):
///  • вжатие 0.94 за 90 мс — отклик заметен раньше 100 мс (правило tap-feedback);
///  • отпускание — пружина (упругий возврат), а не линейный откат;
///  • пока палец на кнопке — под ней разгорается тёплое гало;
///  • на отпускании — расходящаяся волна-всплеск от края кнопки;
///  • в отключённом состоянии кнопка едва заметно «дышит», приглашая нажать.
/// Всё это отключается флагом [animate] (Lite-режим) и не двигает соседние
/// элементы — анимируются только transform/opacity, без reflow.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));

  // «энергия» кольца: 1 при свежем подключении, спадает к ~0.35 (стабильно).
  late final AnimationController _energy = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  // мягкое затухание энергии (без линейного «спада рывком»)
  late final Animation<double> _energyCurve =
      CurvedAnimation(parent: _energy, curve: Curves.easeOutCubic);

  // --- нажатие ---
  // Глубина вжатия 0..1. Вниз — быстро (90 мс), вверх — пружиной: именно этот
  // «отскок» и даёт приятное тактильное ощущение.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 620),
  );
  // Вниз — быстрый ease-out (палец сразу чувствует отклик), вверх — мягкая
  // пружина: короткий, но заметный «дышащий» отскок без дребезга.
  late final Animation<double> _pressCurve = CurvedAnimation(
    parent: _press,
    curve: Curves.easeOutCubic,
    reverseCurve: const _SoftSpring(),
  );

  // Волна-всплеск от края кнопки на отпускании (одноразовая).
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Едва заметное «дыхание», когда VPN выключен — подсказывает, что можно нажать.
  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

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
      if (!widget.connected && !_breathe.isAnimating) _breathe.repeat();
    } else {
      _spin.stop();
      _pulse.stop();
      _breathe.stop();
    }
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) _syncAnim();
    if (widget.connected != old.connected) {
      // «дышит» только в покое — при активном соединении живёт кольцо
      if (widget.connected) {
        _breathe.stop();
      } else if (widget.animate && !_breathe.isAnimating) {
        _breathe.repeat();
      }
    }
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
    _press.dispose();
    _burst.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _onDown() {
    if (widget.busy || !widget.animate) return;
    HapticFeedback.selectionClick(); // отклик пальцу раньше, чем визуал
    _press.forward();
  }

  void _onUp({bool fire = true}) {
    if (!widget.animate) return;
    if (_press.value > 0) _press.reverse();
    if (fire && !widget.busy) _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.busy ? null : widget.onTap,
      onTapDown: (_) => _onDown(),
      onTapUp: (_) => _onUp(),
      onTapCancel: () => _onUp(fire: false),
      child: SizedBox(
        width: 168,
        height: 168,
        child: AnimatedBuilder(
          animation: Listenable.merge(
              [_spin, _pulse, _energyCurve, _pressCurve, _burst, _breathe]),
          builder: (context, _) {
            // энергия: до окончания контроллера 1→0 (плавно), дальше держим 0.35
            final raw = widget.connected ? (1 - _energyCurve.value) : 0.0;
            final energy = widget.connected ? (0.35 + 0.65 * raw) : 0.0;
            // 0..1, но упруго выходит за 1 на возврате — отсюда «отскок»
            final press = _pressCurve.value.clamp(0.0, 1.35);
            // спокойное дыхание в покое: ±0.8% масштаба
            final breath = (!widget.connected && widget.animate)
                ? math.sin(_breathe.value * 2 * math.pi) * 0.008
                : 0.0;
            final scale = 1.0 + breath - 0.055 * press;

            return Transform.scale(
              scale: scale,
              child: CustomPaint(
                painter: _RingPainter(
                  spin: _spin.value,
                  pulse: _pulse.value,
                  energy: energy,
                  connected: widget.connected,
                  press: press,
                  burst: _burst.isAnimating || _burst.value > 0
                      ? _burst.value
                      : 0.0,
                  busy: widget.busy,
                ),
                child: Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.4),
                        colors: [Color(0xFF131D33), Color(0xFF080E1A)],
                      ),
                      border: Border.fromBorderSide(BorderSide(
                        // при нажатии кромка разгорается — «кнопка ожила»
                        color: Color.lerp(const Color(0x335E2C9E),
                            P.lime.withValues(alpha: 0.55), press.clamp(0, 1))!,
                      )),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Иконка остаётся на месте всегда: при подключении
                        // «дышит» яркостью, а прогресс показывают дуги по
                        // кольцу. Раньше иконка подменялась спиннером — центр
                        // кнопки дёргался, и переход выглядел рвано.
                        TweenAnimationBuilder<Color?>(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          tween: ColorTween(
                              end: widget.connected
                                  ? P.limeText
                                  : (widget.busy ? P.lime : P.textFaint)),
                          builder: (_, color, __) => Opacity(
                            opacity: widget.busy
                                ? 0.55 +
                                    0.45 *
                                        (0.5 +
                                            0.5 *
                                                math.sin(
                                                    _pulse.value * 2 * math.pi))
                                : 1,
                            child: Icon(Icons.power_settings_new_rounded,
                                size: 40, color: color),
                          ),
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
              ),
            );
          },
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
  final double press; // 0..1.35 — глубина вжатия (с упругим выбегом)
  final double burst; // 0..1 — волна на отпускании
  final bool busy; // идёт подключение — рисуем «живую» дугу
  _RingPainter({
    required this.spin,
    required this.pulse,
    required this.energy,
    required this.connected,
    required this.press,
    required this.burst,
    required this.busy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 2 - 24;
    final p = press.clamp(0.0, 1.0);

    // Гало под пальцем: мягкое свечение, разгорается вместе с вжатием.
    if (p > 0.01) {
      canvas.drawCircle(
          c,
          base - 6 + 10 * p,
          Paint()
            ..color =
                (connected ? P.lime : P.violet).withValues(alpha: 0.22 * p)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    }

    // Волна-всплеск на отпускании: уходит от края и гаснет.
    if (burst > 0 && burst < 1) {
      final t = Curves.easeOutCubic.transform(burst);
      canvas.drawCircle(
          c,
          base + 6 + t * 46,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - t) + 0.5
            ..color = (connected ? P.lime : P.violet)
                .withValues(alpha: 0.5 * (1 - t)));
    }

    // ПОДКЛЮЧЕНИЕ: две встречные дуги по кольцу + мягкое дыхание свечения.
    // Заметно живее статичного индикатора и сразу говорит «идёт работа».
    if (busy) {
      final r = base + 4;
      final rect = Rect.fromCircle(center: c, radius: r);
      final glow = 0.5 + 0.5 * math.sin(spin * 4 * math.pi);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = P.lime.withValues(alpha: 0.10 + 0.10 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      for (var i = 0; i < 2; i++) {
        final dir = i == 0 ? 1 : -1;
        final start = spin * 2 * math.pi * dir + i * math.pi;
        canvas.drawArc(
            rect,
            start,
            math.pi * 0.42,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 4.5
              ..color = (i == 0 ? P.lime : P.violet).withValues(alpha: 0.85)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      }
    }

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
          P.lime,
          P.violet,
          P.lime,
          P.violet,
          P.lime,
        ],
      );
      canvas.drawCircle(
          c,
          base + 4,
          Paint()
            ..style = PaintingStyle.stroke
            // под пальцем кольцо чуть толще и ярче — реакция на касание
            ..strokeWidth = 6 + energy * 6 + 2 * p
            ..shader =
                sweep.createShader(Rect.fromCircle(center: c, radius: base + 4))
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, 3 + energy * 6 + 3 * p));
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

/// Мягкая пружина для возврата кнопки после нажатия.
///
/// Curves.elasticOut даёт длинный «дребезг» с несколькими затухающими
/// колебаниями — на большой кнопке это выглядит дёшево. Здесь одно короткое
/// перелетание за край и спокойное затухание: ощущается как упругий материал,
/// а не как резинка.
class _SoftSpring extends Curve {
  const _SoftSpring();

  @override
  double transformInternal(double t) {
    const damping = 6.5; // как быстро гаснет
    const frequency = 2.4; // сколько колебаний успеет за возврат
    return 1 - math.exp(-damping * t) * math.cos(frequency * math.pi * t);
  }
}
