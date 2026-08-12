/// Профиль и подписка: статус, привязанный Telegram-ID, продление, рефералка,
/// ссылка на канал. Детали подписки живут в боте — отсюда быстрый переход.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/brand_logo.dart';
import '../widgets/connect_ways.dart';
import '../widgets/streak_flame.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Профиль и Главная показывают ОДНУ дату — из общего состояния AppState
    // (source of truth = refreshSubStatus → /me + кэш). Раньше профиль делал
    // свой запрос и для админа рисовал фейковую now+30 → дата не совпадала с
    // главной. Теперь просто обновляем статус и стрик из единого места.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      state.refreshSubStatus();
      state.loadStreak();
    });
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Привязка подписки — тем же единым блоком, что и везде в приложении
  /// (ID главным, ссылка и QR альтернативами), а не отдельным диалогом.
  Future<void> _linkTelegram() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(L.t('link_tg'),
                style: const TextStyle(
                    color: P.text, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          ConnectWays(
            compact: true,
            onSuccess: () => Navigator.of(ctx).maybePop(),
          ),
        ]),
      ),
    );
    // ConnectWays уже обновляет статус и стрик, а
    // context.watch<AppState> в build перерисует экран.
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tgId = Storage.instance.tgId;
    // Подписка активна, если так сказал бэкенд (subActive), либо есть
    // импортированные конфиги. Дата — общая из состояния (та же, что на главной).
    // Статус — только реальная подписка (серверы есть у всех, доступом не являются).
    final hasSub = state.subActive;
    final until = state.subUntil;
    final loading = !state.subLoaded && tgId != null && tgId.isNotEmpty;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          const Center(child: BrandLogo(size: 76)),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                if (tgId != null && state.profileUsername.isNotEmpty)
                  Text('@${state.profileUsername}',
                      style: const TextStyle(
                          color: P.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                Text(
                  tgId != null ? 'ID: $tgId' : L.t('account_not_linked'),
                  style: TextStyle(
                      color: tgId != null && state.profileUsername.isNotEmpty
                          ? P.textFaint
                          : P.text,
                      fontSize: tgId != null && state.profileUsername.isNotEmpty
                          ? 12
                          : 15),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: P.limeText)),
              ),
            ),
          const SizedBox(height: 18),

          // статус подписки
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: hasSub ? P.grad : null,
              color: hasSub ? null : P.surfaceLo,
              borderRadius: BorderRadius.circular(16),
              border: hasSub ? null : Border.all(color: P.surfaceHi),
            ),
            child: Row(
              children: [
                Icon(hasSub ? Icons.verified : Icons.lock_outline,
                    color: hasSub ? P.onLime : P.textFaint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hasSub ? L.t('sub_active') : L.t('sub_inactive'),
                          style: TextStyle(
                              color: hasSub ? P.onLime : P.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(
                          hasSub
                              ? (until != null
                                  ? '${L.t('valid_until')} ${_fmtDate(until)}'
                                  : L.t('full_access'))
                              : L.t('subscribe_hint'),
                          style: TextStyle(
                              color: hasSub ? P.onLimeDim : P.textFaint,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // карточка серии («огонёк») — награда за ежедневное пользование
          _StreakCard(state: state),
          const SizedBox(height: 18),

          if (tgId == null)
            _Tile(
              icon: Icons.link,
              title: L.t('link_tg'),
              subtitle: L.t('link_tg_d'),
              onTap: _linkTelegram,
            ),
          _Tile(
            icon: Icons.workspace_premium,
            title: hasSub ? L.t('renew') : L.t('subscribe'),
            onTap: () => _open('${Brand.bot}?start=renew'),
          ),
          _Tile(
            icon: Icons.card_giftcard,
            title: L.t('invite'),
            subtitle: L.t('invite_d'),
            onTap: () => _open('${Brand.bot}?start=invite'),
          ),
          // Канал вместо копирования ID: сам ID виден выше и его можно
          // выделить, а вот дороги в канал из профиля не было вовсе.
          _Tile(
            icon: Icons.campaign_outlined,
            title: L.t('our_channel'),
            subtitle: Brand.channel.replaceFirst('https://t.me/', '@'),
            onTap: () => _open(Brand.channel),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final AppState state;
  const _StreakCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final streak = state.streak;
    final next = state.streakNextMilestone;
    final rewards = state.streakRewards;
    final nextReward = rewards[next] ?? 0;
    final progress = (next > 0 && streak >= 0)
        ? (streak / next).clamp(0.0, 1.0)
        : (streak > 0 ? 1.0 : 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: P.surfaceHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StreakFlame(days: streak, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        streak > 0
                            ? L.t('streak_title_on',
                                {'n': streak, 'w': L.days(streak)})
                            : L.t('streak_title_off'),
                        style: const TextStyle(
                            color: P.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        streak > 0
                            ? L.t('streak_hint_on')
                            : L.t('streak_hint_off'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: P.textFaint, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // прогресс до следующей награды
          if (next > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: P.surfaceHi,
                valueColor: const AlwaysStoppedAnimation(P.limeText),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                L.t('streak_next', {
                  'r': nextReward,
                  'rw': L.days(nextReward),
                  'd': (next - streak).clamp(0, next),
                  'dw': L.days((next - streak).clamp(0, next)),
                  'm': next
                }),
                style: const TextStyle(color: P.textDim, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          // заморозки
          Row(
            children: [
              const Icon(Icons.ac_unit, color: P.limeText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(L.t('streak_freezes', {'n': state.streakFreezes}),
                    style: const TextStyle(color: P.textFaint, fontSize: 11.5)),
              ),
            ],
          ),
          if (rewards.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: P.surfaceHi, height: 1),
            const SizedBox(height: 10),
            Text(L.t('streak_rewards'),
                style: const TextStyle(
                    color: P.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in (rewards.keys.toList()..sort()))
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: streak >= m
                          ? P.violet.withValues(alpha: 0.35)
                          : P.surfaceHi,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: streak >= m ? P.limeText : P.surfaceHi),
                    ),
                    child: Text(
                        '$m ${L.t('streak_day_short')} → +${rewards[m]}',
                        style: TextStyle(
                            color: streak >= m ? P.limeText : P.textDim,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _Tile(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.surfaceHi),
      ),
      // Material поверх подложки: ListTile рисует подсветку нажатия на
      // ближайшем Material, а цветной контейнер её перекрывал — нажатия
      // выглядели «мёртвыми», без отклика.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(icon, color: P.limeText),
          title:
              Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
          subtitle: subtitle != null
              ? Text(subtitle!,
                  style: const TextStyle(color: P.textFaint, fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right, color: P.textFaint),
          onTap: onTap,
        ),
      ),
    );
  }
}
