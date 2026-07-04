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

  // Премиальная вводная инструкция по всему сервису (первый запуск), двуязычная.
  List<({IconData icon, String title, String body})> get _slides =>
      L.current == 'en' ? _slidesEn : _slidesRu;

  static const _slidesRu = [
    (
      icon: Icons.public,
      title: 'Добро пожаловать в Various VPN',
      body: 'Твой личный премиум-VPN: быстрый, умный и без блокировок. '
          'За пару секунд покажем всё, что он умеет — это займёт полминуты.'
    ),
    (
      icon: Icons.bolt,
      title: 'Подключение в один тап',
      body: 'Нажми большую кнопку на главном экране — приложение само выберет '
          'самый быстрый рабочий сервер и проверит связь. Если сеть «спит» после '
          'простоя — переподключит незаметно, ждать не нужно.'
    ),
    (
      icon: Icons.smart_toy_outlined,
      title: 'Умный доступ к нейросетям',
      body: 'ChatGPT, Gemini, Claude открываются всегда: приложение само находит '
          'сервер, где ИИ работает, даже если на ближайшем он заблокирован. '
          'Включается тумблером в настройках.'
    ),
    (
      icon: Icons.alt_route,
      title: 'Раздельное туннелирование',
      body: 'Российские сайты и банки идут напрямую (быстро, без VPN), а всё '
          'остальное — через защищённый туннель. Можно выбрать, какие приложения '
          'пускать через VPN, а какие — мимо.'
    ),
    (
      icon: Icons.local_fire_department,
      title: 'Огонёк серии 🔥 — награды за верность',
      body: 'Пользуйся VPN каждый день — растёт серия (стрик). За вехи 7, 30, 90, '
          '180 и 365 дней начисляем бонусные дни подписки автоматически. '
          'Активность 25+ ч в неделю даёт «заморозки», которые спасают серию, '
          'если пропустишь день.'
    ),
    (
      icon: Icons.flash_on,
      title: 'Режим «По требованию»',
      body: 'Включи On-Demand в настройках — и VPN будет подниматься сам при '
          'запуске приложения. А ещё: обход блокировок по современным протоколам '
          'Reality/Hysteria2 и защита от DPI.'
    ),
    (
      icon: Icons.card_giftcard,
      title: 'Бонусы и поддержка',
      body: 'Приглашай друзей и получай дни + процент с их оплат. Есть вопрос — '
          'пиши прямо в приложении, ответим быстро. Следи за новостями в нашем '
          'Telegram-канале. Погнали! 🚀'
    ),
  ];

  static const _slidesEn = [
    (
      icon: Icons.public,
      title: 'Welcome to Various VPN',
      body: 'Your personal premium VPN: fast, smart and unblockable. '
          'In a few seconds we\'ll show everything it can do — takes half a minute.'
    ),
    (
      icon: Icons.bolt,
      title: 'One-tap connection',
      body: 'Tap the big button on the home screen — the app picks the fastest '
          'working server and verifies the link. If the network was asleep after '
          'idle, it reconnects invisibly — no waiting.'
    ),
    (
      icon: Icons.smart_toy_outlined,
      title: 'Smart access to AI',
      body: 'ChatGPT, Gemini, Claude always open: the app finds a server where AI '
          'works, even if it\'s blocked on the nearest one. Toggle it in settings.'
    ),
    (
      icon: Icons.alt_route,
      title: 'Split tunneling',
      body: 'Local sites and banks go direct (fast, no VPN), everything else '
          'through the secure tunnel. You choose which apps go through the VPN.'
    ),
    (
      icon: Icons.local_fire_department,
      title: 'Streak flame 🔥 — loyalty rewards',
      body: 'Use the VPN daily — your streak grows. At 7, 30, 90, 180 and 365 days '
          'we credit bonus subscription days automatically. 25+ h a week earns '
          '“freezes” that save your streak if you miss a day.'
    ),
    (
      icon: Icons.flash_on,
      title: 'On-Demand mode',
      body: 'Enable On-Demand in settings and the VPN comes up on app launch. '
          'Plus: anti-block via modern Reality/Hysteria2 protocols and DPI defense.'
    ),
    (
      icon: Icons.card_giftcard,
      title: 'Bonuses & support',
      body: 'Invite friends and earn days + a share of their payments. Questions? '
          'Message us right in the app. Follow news in our Telegram channel. Let\'s go! 🚀'
    ),
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
                            Text(s.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: P.text, fontSize: 22),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 14),
                            Text(s.body,
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
