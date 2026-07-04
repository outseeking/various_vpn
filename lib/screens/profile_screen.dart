/// Профиль и подписка: статус, привязанный Telegram-ID, продление, рефералка,
/// ссылка на канал. Детали подписки живут в боте — отсюда быстрый переход.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/brand_logo.dart';
import '../widgets/streak_flame.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ({bool active, DateTime? until})? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final tgId = Storage.instance.tgId;
    // подтягиваем актуальный стрик для карточки серии
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadStreak();
    });
    if (tgId != null && tgId.isNotEmpty) {
      _loading = true;
      BackendApi().subStatus(tgId).then((s) {
        if (mounted) {
          setState(() {
            _status = s;
            _loading = false;
          });
        }
      });
    }
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Future<void> _linkTelegram() async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('link_tg')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.t('link_tg_hint'),
                style: const TextStyle(color: P.textFaint, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: P.text),
              decoration: const InputDecoration(
                hintText: '123456789',
                hintStyle: TextStyle(color: P.textFaint),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(L.t('save')),
          ),
        ],
      ),
    );
    if (id != null && id.isNotEmpty && mounted) {
      final state = context.read<AppState>();
      state.setTgId(id);
      await state.refreshSubStatus();
      await state.loadStreak(); // подтянуть ник и стрик к профилю
      final s = await BackendApi().subStatus(id);
      if (mounted) setState(() => _status = s);
    }
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tgId = Storage.instance.tgId;
    // Подписка активна, если так сказал бэкенд, либо есть импортированные конфиги.
    final hasSub = _status?.active ?? state.hasServers;
    final until = _status?.until;
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
                      color: tgId != null &&
                              state.profileUsername.isNotEmpty
                          ? P.textFaint
                          : P.text,
                      fontSize: tgId != null &&
                              state.profileUsername.isNotEmpty
                          ? 12
                          : 15),
                ),
              ],
            ),
          ),
          if (_loading)
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
                    color: hasSub ? const Color(0xFF0C1206) : P.textFaint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hasSub ? L.t('sub_active') : L.t('sub_inactive'),
                          style: TextStyle(
                              color: hasSub ? const Color(0xFF0C1206) : P.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(
                          hasSub
                              ? (until != null
                                  ? '${L.t('valid_until')} ${_fmtDate(until)}'
                                  : L.t('full_access'))
                              : L.t('subscribe_hint'),
                          style: TextStyle(
                              color: hasSub
                                  ? const Color(0xCC0C1206)
                                  : P.textFaint,
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
          _Tile(
            icon: Icons.campaign,
            title: L.t('channel'),
            subtitle: L.t('channel_d'),
            onTap: () => _open(Brand.channel),
          ),
          if (tgId != null)
            _Tile(
              icon: Icons.copy,
              title: L.t('copy_id'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: tgId));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('ID скопирован'),
                  backgroundColor: P.surface,
                ));
              },
            ),
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
                    Text(streak > 0 ? 'Серия: $streak дней подряд' : 'Начни серию!',
                        style: const TextStyle(
                            color: P.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        streak > 0
                            ? 'Заходи каждый день — не потеряй огонёк 🔥'
                            : 'Подключай VPN каждый день и получай бонусные дни',
                        style: const TextStyle(color: P.textFaint, fontSize: 12)),
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
            Text('До награды +$nextReward дней: осталось ${(next - streak).clamp(0, next)} дн. '
                '(веха $next)',
                style: const TextStyle(color: P.textDim, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          // заморозки
          Row(
            children: [
              const Icon(Icons.ac_unit, color: P.limeText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Заморозки: ${state.streakFreezes} '
                    '· копятся за 25+ ч VPN в неделю и спасают серию при пропуске дня',
                    style: const TextStyle(color: P.textFaint, fontSize: 11.5)),
              ),
            ],
          ),
          if (rewards.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: P.surfaceHi, height: 1),
            const SizedBox(height: 10),
            const Text('Награды за серию',
                style: TextStyle(
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
                      color: streak >= m ? P.violet.withValues(alpha: 0.35) : P.surfaceHi,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: streak >= m ? P.limeText : P.surfaceHi),
                    ),
                    child: Text('$m дн → +${rewards[m]}',
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
      child: ListTile(
        leading: Icon(icon, color: P.limeText),
        title: Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(color: P.textFaint, fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right, color: P.textFaint),
        onTap: onTap,
      ),
    );
  }
}
