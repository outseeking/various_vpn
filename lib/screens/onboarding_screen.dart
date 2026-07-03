/// Онбординг: 3 слайда о преимуществах с подвижными анимациями (тёмная тема).
/// Показывается только при первом запуске → дальше сразу главный экран.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/storage.dart';
import '../theme/app_palette.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _page = 0;

  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..repeat();

  static const _slides = [
    (icon: Icons.alt_route, titleKey: 'ob1_title', bodyKey: 'ob1_body'),
    (icon: Icons.bolt, titleKey: 'ob2_title', bodyKey: 'ob2_body'),
    (icon: Icons.shield_outlined, titleKey: 'ob3_title', bodyKey: 'ob3_body'),
  ];

  void _finish() {
    Storage.instance.onboardingDone = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: P.bg,
      body: Stack(
        children: [
          // живой фон из цветных пятен
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(
              size: Size.infinite,
              painter: _BlobPainter(_anim.value),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(L.t('skip'),
                        style: const TextStyle(color: P.textFaint)),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final s = _slides[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Hero(icon: s.icon, anim: _anim),
                            const SizedBox(height: 36),
                            Text(L.t(s.titleKey),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: P.text, fontSize: 22),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 14),
                            Text(L.t(s.bodyKey),
                                style: const TextStyle(
                                    color: P.textDim,
                                    fontSize: 15,
                                    height: 1.5),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.all(4),
                      width: i == _page ? 22 : 8,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: i == _page ? P.grad : null,
                        color: i == _page ? null : P.surfaceHi,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: GestureDetector(
                    onTap: () {
                      if (last) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: P.lime,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(last ? L.t('start') : L.t('next'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFF0C1206),
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Парящая иконка с двумя вращающимися кольцами.
class _Hero extends StatelessWidget {
  final IconData icon;
  final Animation<double> anim;
  const _Hero({required this.icon, required this.anim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final t = anim.value * 2 * math.pi;
        final float = math.sin(t) * 7;
        return Transform.translate(
          offset: Offset(0, float),
          child: SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: t,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: P.lime.withValues(alpha: 0.30), width: 1.5),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: -t * 0.7,
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: P.violet.withValues(alpha: 0.40), width: 1),
                    ),
                  ),
                ),
                ShaderMask(
                  shaderCallback: (r) => P.grad.createShader(r),
                  child: Icon(icon, size: 46, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Анимированные цветные пятна на фоне.
class _BlobPainter extends CustomPainter {
  final double t;
  _BlobPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    void blob(Offset base, double rad, Color color, double phase) {
      final off = Offset(
        base.dx + math.cos(a + phase) * 22,
        base.dy + math.sin(a + phase) * 18,
      );
      canvas.drawCircle(
          off,
          rad,
          Paint()
            ..color = color.withValues(alpha: 0.13)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    }

    blob(Offset(size.width * 0.2, size.height * 0.18), 130, P.lime, 0);
    blob(Offset(size.width * 0.85, size.height * 0.5), 140, P.violet, 2);
    blob(Offset(size.width * 0.4, size.height * 0.85), 120, P.lime, 4);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.t != t;
}
