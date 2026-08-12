/// Экран входа — первое, что видит человек после онбординга. Порядок блоков
/// подчинён воронке:
///   1) «3 дня бесплатно» — главный оффер для новичка (у него ещё нет ID);
///   2) «Тарифы» с ценой «от N ₽» — чтобы не идти в бота на разведку;
///   3) ConnectWays — для тех, кто уже оплатил: ID главным, ссылка/QR запасными.
/// Переключатель языка стоит в шапке: язык нужен до, а не после онбординга.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../theme/app_palette.dart';
import '../state/app_state.dart';
import '../widgets/brand_logo.dart';
import '../widgets/connect_ways.dart';
import '../widgets/lang_switch.dart';
import '../widgets/tap_scale.dart';
import 'home_screen.dart';
import 'connect_guide_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _bg =
      AnimationController(vsync: this, duration: const Duration(seconds: 14))
        ..repeat();

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  /// «Попробовать 3 дня бесплатно»: сразу поднимаем бесплатный Telegram-режим
  /// (иначе у человека с блокировками просто не откроется бот) и уводим в бота
  /// за триалом. Одна кнопка вместо двух — меньше выбора, меньше потерь.
  Future<void> _startTrial() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Поднимаем бесплатный Telegram В ФОНЕ (система спросит разрешение на
    // VPN-профиль) и сразу ведём на экран-объяснение: что сейчас произойдёт,
    // зачем разрешение и что делать в боте. Без него человек уходил в бота
    // «вслепую» и возвращался, не понимая, куда нажимать.
    final state = context.read<AppState>();
    // У кого подписка уже активна, инструкции про бесплатный режим не нужны:
    // ему всё доступно, и лишний экран между ним и приложением — просто
    // препятствие. Ведём сразу на главный.
    if (state.hasAccess) {
      setState(() => _busy = false);
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
      return;
    }
    unawaited(state.connectTelegramOnly());
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ConnectGuideScreen(afterFreeEnable: true)));
  }

  @override
  Widget build(BuildContext context) {
    // Без подписки на AppState тумблер языка перерисовывал только себя, а
    // тексты экрана оставались на старом языке.
    context.watch<AppState>();
    return Scaffold(
      backgroundColor: P.bg,
      body: Stack(
        children: [
          // живой фон из мягких пятен (как в онбординге) — «дорого» и без рывков
          AnimatedBuilder(
            animation: _bg,
            builder: (_, __) => CustomPaint(
                size: Size.infinite, painter: _BlobPainter(_bg.value)),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
              children: [
                // Переключатель языка с ПЕРВОГО экрана: раньше язык менялся
                // только в настройках, то есть уже после онбординга на чужом
                // языке. Стоит в углу и не спорит с главным действием.
                const Align(
                    alignment: Alignment.centerRight, child: LangSwitch()),
                const SizedBox(height: 4),
                Center(child: _FloatingLogo(anim: _bg)),
                const SizedBox(height: 18),
                Center(
                  child: ShaderMask(
                    shaderCallback: (r) => P.grad.createShader(r),
                    child: const Text('Various VPN',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(L.t('gs_tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: P.textDim, fontSize: 14)),
                const SizedBox(height: 16),
                // Плашки доверия (как у топовых VPN) — коротко про главное.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TrustBadge(
                        icon: Icons.auto_awesome, text: L.t('gs_badge_ru')),
                    _TrustBadge(icon: Icons.devices, text: L.t('gs_badge_dev')),
                    _TrustBadge(
                        icon: Icons.lock_outline, text: L.t('gs_badge_nolog')),
                  ],
                ),
                const SizedBox(height: 28),

                // 1) ГЛАВНЫЙ ОФФЕР — триал. Стоит первым: у новичка ещё
                // нет ID, и именно эта кнопка должна попадаться на глаза
                // раньше всего. Сама включает Telegram и ведёт на объяснение.
                _ShineButton(
                  step: 1,
                  title: L.t('gs_get_sub'),
                  subtitle: L.t('gs_trial_d'),
                  anim: _bg,
                  onTap: _startTrial,
                ),
                const SizedBox(height: 10),
                // Снятие возражений прямо под главной кнопкой: человек боится
                // не цены, а того, что его привяжут к карте и спишут молча.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _NoRisk(text: L.t('gs_risk_card')),
                    _NoRisk(text: L.t('gs_risk_auto')),
                    _NoRisk(text: L.t('gs_risk_min')),
                  ],
                ),
                const SizedBox(height: 20),

                // 2) УЖЕ ЕСТЬ ПОДПИСКА — единый блок на всё приложение:
                // ID главным, ссылка и QR альтернативами (см. ConnectWays).
                //
                // Карточки «Тарифы и оплата» между этими двумя путями больше
                // нет: она перебивала главную кнопку и уводила в бота того,
                // кто ещё ничего не попробовал. Тарифы никуда не делись —
                // они там же, в боте, куда ведёт сама кнопка триала.
                ConnectWays(
                  onSuccess: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MainShell())),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Короткая строка «нечем рисковать» — галочка + два-три слова.
class _NoRisk extends StatelessWidget {
  final String text;
  const _NoRisk({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_rounded, size: 14, color: P.limeText),
      const SizedBox(width: 5),
      Text(text,
          style: const TextStyle(
              color: P.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Компактная плашка доверия (иконка + короткий текст).
class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TrustBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: P.surfaceHi),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: P.limeText),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                color: P.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Главная кнопка с бегущим световым бликом по градиенту.
class _ShineButton extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final Animation<double> anim;
  final VoidCallback onTap;
  const _ShineButton({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.anim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      scale: 0.97,
      child: AnimatedBuilder(
        animation: anim,
        builder: (_, __) {
          final shine = (anim.value * 2) % 1.0; // 0..1 бежит по кнопке
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: P.grad,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: P.lime.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: -4,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(
              children: [
                // бегущий блик
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CustomPaint(painter: _ShinePainter(shine)),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: P.onLimeGhost,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: P.onLime, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(title,
                                  style: const TextStyle(
                                      color: P.onLime,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(subtitle,
                              style: const TextStyle(
                                  color: P.onLimeDim,
                                  fontSize: 12.5,
                                  height: 1.35)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: P.onLime),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShinePainter extends CustomPainter {
  final double t; // 0..1
  _ShinePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Диагональный блик во всю карточку (а не узкая полоса по центру): широкая
    // мягкая полоса едет слева направо под наклоном, поэтому «переливается» весь
    // прямоугольник целиком.
    final band = w * 0.5;
    final cx = t * (w + h * 2 + band) - h - band;
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(cx + band, 0)
      ..lineTo(cx + band - h, h)
      ..lineTo(cx - h, h)
      ..close();
    final rect = Rect.fromLTWH(cx - h, 0, band + h, h);
    canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0x00FFFFFF),
              Color(0x4DFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _ShinePainter old) => old.t != t;
}

/// Вторичная карточка-путь (бесплатно / есть ссылка).
class _FloatingLogo extends StatelessWidget {
  final Animation<double> anim;
  const _FloatingLogo({required this.anim});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final float = math.sin(anim.value * 2 * math.pi) * 6;
        return Transform.translate(
            offset: Offset(0, float), child: const BrandLogo(size: 88));
      },
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  _BlobPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    void blob(Offset base, double rad, Color color, double phase) {
      final off = Offset(base.dx + math.cos(a + phase) * 22,
          base.dy + math.sin(a + phase) * 18);
      canvas.drawCircle(
          off,
          rad,
          Paint()
            ..color = color.withValues(alpha: 0.13)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    }

    blob(Offset(size.width * 0.2, size.height * 0.16), 130, P.lime, 0);
    blob(Offset(size.width * 0.85, size.height * 0.42), 140, P.violet, 2);
    blob(Offset(size.width * 0.4, size.height * 0.8), 120, P.lime, 4);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.t != t;
}
