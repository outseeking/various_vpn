/// Огонёк серии (стрик) в стиле Various VPN + премиальная анимация награды.
///
/// [StreakFlame] — компактный анимированный огонёк с числом дней (для профиля/
/// карточек). [StreakCelebration] — полноэкранное празднование при взятии вехи:
/// вспышка, разлетающиеся искры, пульсирующий огонь в палитре приложения.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_palette.dart';

/// Компактный живой огонёк с числом дней серии.
class StreakFlame extends StatefulWidget {
  final int days;
  final double size;
  final bool animate;
  const StreakFlame(
      {super.key, required this.days, this.size = 48, this.animate = true});

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);
  double _time = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
      _last = now;
      if (widget.animate) {
        _time += dt;
        _t.value = _time;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size * 1.15,
      child: CustomPaint(
        painter: _FlamePainter(_t),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: widget.size * 0.28),
            child: Text('${widget.days}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: widget.size * 0.36,
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                )),
          ),
        ),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final ValueNotifier<double> t;
  _FlamePainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final cx = size.width / 2;
    final w = size.width, h = size.height;
    // «дыхание» пламени
    final flick = 0.5 + 0.5 * math.sin(time * 6);
    final flick2 = 0.5 + 0.5 * math.sin(time * 9 + 1.3);

    Path flame(double scale, double sway) {
      final p = Path();
      final baseY = h * 0.98;
      final tipY = h * (0.06 + 0.05 * flick) * 1;
      final width = w * 0.42 * scale;
      p.moveTo(cx, baseY);
      p.cubicTo(cx - width, h * 0.78, cx - width * 0.9,
          h * 0.42 + sway, cx + sway * 0.4, tipY);
      p.cubicTo(cx + width * 0.9, h * 0.42 - sway, cx + width, h * 0.78,
          cx, baseY);
      p.close();
      return p;
    }

    // внешнее свечение
    canvas.drawCircle(
        Offset(cx, h * 0.6),
        w * 0.5,
        Paint()
          ..color = P.lime.withValues(alpha: 0.18 + 0.10 * flick)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    // тело пламени: лайм → фиолет (палитра приложения)
    canvas.drawPath(
        flame(1.0, math.sin(time * 5) * w * 0.02),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [P.violet, P.lime, P.limeText],
          ).createShader(Rect.fromLTWH(0, 0, w, h))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
    // внутреннее ядро — ярче
    canvas.drawPath(
        flame(0.55, math.sin(time * 7 + 0.6) * w * 0.02),
        Paint()..color = Colors.white.withValues(alpha: 0.55 + 0.35 * flick2));
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => true;
}

/// Полноэкранное празднование награды за веху серии.
class StreakCelebration extends StatefulWidget {
  final int milestone; // сколько дней подряд
  final int rewardDays; // сколько дней начислено
  final VoidCallback onClose;
  const StreakCelebration({
    super.key,
    required this.milestone,
    required this.rewardDays,
    required this.onClose,
  });

  @override
  State<StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<StreakCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650))
        ..forward();
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);
  double _time = 0;
  Duration _last = Duration.zero;
  late final List<_Spark> _sparks = List.generate(28, (i) => _Spark(i));

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
      _last = now;
      _time += dt;
      _t.value = _time;
    })..start();
  }

  @override
  void dispose() {
    _in.dispose();
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: GestureDetector(
        onTap: widget.onClose,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // искры на фоне
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SparksPainter(_t, _sparks)),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _in, curve: Curves.elasticOut),
                child: FadeTransition(
                  opacity: _in,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 172,
                        child: StreakFlame(days: widget.milestone, size: 130),
                      ),
                      const SizedBox(height: 8),
                      const Text('СЕРИЯ ПРОДОЛЖАЕТСЯ!',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: 1.5,
                          )),
                      const SizedBox(height: 10),
                      Text('${widget.milestone} дней подряд с Various VPN',
                          style: const TextStyle(color: P.textDim, fontSize: 15)),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [P.violet, P.lime]),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                                color: P.lime.withValues(alpha: 0.5),
                                blurRadius: 24,
                                spreadRadius: 1),
                          ],
                        ),
                        child: Text('🎁  +${widget.rewardDays} дней подписки',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            )),
                      ),
                      const SizedBox(height: 14),
                      Text('Начислено автоматически · тапни, чтобы закрыть',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spark {
  final double angle, speed, radius, phase, sizePx;
  final bool lime;
  _Spark(int i)
      : angle = (i * 2654435761 % 628) / 100.0,
        speed = 0.5 + (i * 40503 % 100) / 100.0,
        radius = 0.2 + (i * 92821 % 100) / 100.0,
        phase = (i * 13 % 100) / 100.0,
        sizePx = 1.5 + (i % 4),
        lime = i % 2 == 0;
}

class _SparksPainter extends CustomPainter {
  final ValueNotifier<double> t;
  final List<_Spark> sparks;
  _SparksPainter(this.t, this.sparks) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final cx = size.width / 2, cy = size.height * 0.42;
    for (final s in sparks) {
      final local = (time * s.speed + s.phase) % 1.0;
      final dist = local * size.width * 0.6 * s.radius;
      final x = cx + math.cos(s.angle) * dist;
      final y = cy + math.sin(s.angle) * dist - local * 40;
      final fade = (1 - local).clamp(0.0, 1.0);
      canvas.drawCircle(
          Offset(x, y),
          s.sizePx * fade,
          Paint()
            ..color = (s.lime ? P.limeText : P.violet)
                .withValues(alpha: 0.9 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }
  }

  @override
  bool shouldRepaint(covariant _SparksPainter old) => true;
}
