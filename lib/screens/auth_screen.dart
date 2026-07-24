/// Начало работы (для новичка / после онбординга). Премиальный тёмный экран с
/// живым фоном и тремя понятными путями:
///   1) Получить подписку — открыть Telegram-бота (главный CTA, с «блеском»).
///   2) Попробовать бесплатно — VPN только для Telegram, работает сразу.
///   3) У меня есть ссылка — импорт подписки.
/// Если Telegram не установлен, ссылка t.me откроется в браузере.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../theme/app_palette.dart';
import '../state/app_state.dart';
import '../widgets/brand_logo.dart';
import '../widgets/tap_scale.dart';
import 'connect_guide_screen.dart';
import 'import_screen.dart';

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

  Future<void> _openBot() async {
    final ok = await launchUrl(Uri.parse(Brand.bot),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: P.surface, content: Text(L.t('gs_bot_manual'))),
      );
    }
  }

  Future<void> _freeTelegram() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    // Бесплатный режим поднимаем В ФОНЕ и СРАЗУ ведём на инструкцию — кнопка
    // всегда реагирует, даже если получение сервера/разрешение VPN занимает
    // время (раньше при неудаче казалось, что «ничего не происходит»).
    unawaited(state.connectTelegramOnly());
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const ConnectGuideScreen(afterFreeEnable: true)));
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 12),
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
                    _TrustBadge(icon: Icons.public, text: L.t('gs_badge_ru')),
                    _TrustBadge(
                        icon: Icons.devices, text: L.t('gs_badge_dev')),
                    _TrustBadge(
                        icon: Icons.lock_outline, text: L.t('gs_badge_nolog')),
                  ],
                ),
                const SizedBox(height: 28),

                // 1) Главный CTA — получить подписку в боте (с бегущим блеском).
                _ShineButton(
                  step: 1,
                  title: L.t('gs_get_sub'),
                  subtitle: L.t('gs_get_sub_d'),
                  anim: _bg,
                  onTap: _openBot,
                ),
                const SizedBox(height: 14),

                // 2) Попробовать бесплатно (Telegram-only).
                _OptionCard(
                  step: 2,
                  icon: Icons.telegram,
                  title: L.t('gs_free'),
                  subtitle: L.t('gs_free_d'),
                  busy: _busy,
                  onTap: _freeTelegram,
                ),
                const SizedBox(height: 14),

                // 3) У меня есть ссылка.
                _OptionCard(
                  step: 3,
                  icon: Icons.link,
                  title: L.t('gs_have_link'),
                  subtitle: L.t('gs_have_link_d'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ImportScreen(firstRun: true))),
                ),
                const SizedBox(height: 22),

                Row(children: [
                  const Icon(Icons.info_outline, size: 16, color: P.textFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(L.t('gs_no_tg'),
                        style: const TextStyle(
                            color: P.textFaint, fontSize: 12, height: 1.4)),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
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
                        color: const Color(0x260C1206),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: Color(0xFF0C1206), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Color(0xFF0C1206),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text(subtitle,
                              style: const TextStyle(
                                  color: Color(0xCC0C1206),
                                  fontSize: 12.5,
                                  height: 1.35)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Color(0xFF0C1206)),
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
class _OptionCard extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;
  const _OptionCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: P.surfaceLo,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: P.surfaceHi),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: P.lime.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: P.limeText))
                  : Icon(icon, color: P.limeText, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: P.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: P.textFaint, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: P.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Парящий логотип бренда.
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
