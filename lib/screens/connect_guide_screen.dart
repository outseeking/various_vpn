/// Инструкция «как подключиться» — показывается после включения бесплатного
/// Telegram-VPN (для тех, кто только скачал приложение из стора). Объясняет, что
/// сейчас работает, как разрешить VPN и как получить полный доступ.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import 'home_screen.dart';
import 'import_screen.dart';
import 'profile_screen.dart';

const _botUrl = 'https://t.me/variousvpnbot';

class ConnectGuideScreen extends StatelessWidget {
  /// true — пришли после включения бесплатного режима (другой заголовок/кнопка).
  final bool afterFreeEnable;
  const ConnectGuideScreen({super.key, this.afterFreeEnable = false});

  @override
  Widget build(BuildContext context) {
    // Экран-инструкция МЕНЯЕТ контекст в зависимости от того, есть ли подписка:
    //  • подписка активна → «всё работает, вот как пользоваться»;
    //  • бесплатный режим  → «сейчас только Telegram, вот как открыть весь интернет».
    final state = context.watch<AppState>();
    final sub = state.subActive;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        title: Text(L.t('guide_title')),
        automaticallyImplyLeading: !afterFreeEnable,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            // --- баннер состояния ---
            if (sub)
              _banner(
                icon: Icons.verified,
                text: L.t('guide_sub_active'),
                srvLine: state.activeServer != null
                    ? '${L.t('free_server_label')}: ${state.activeServer!.countryName}'
                    : null,
              )
            else if (afterFreeEnable)
              _banner(
                icon: state.isConnected ? Icons.check_circle : Icons.sync,
                text: state.isConnected
                    ? L.t('guide_free_connected')
                    : L.t('guide_free_on'),
                srvLine: state.activeServer != null
                    ? '${L.t('free_server_label')}: ${state.activeServer!.countryName} · ${L.t('free_only_tg')}'
                    : null,
              ),
            const SizedBox(height: 18),
            Text(L.t('guide_next'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: P.text, fontSize: 20)),
            const SizedBox(height: 16),

            // --- шаги под текущий контекст ---
            _Step(
              n: 1,
              icon: Icons.vpn_key,
              title: L.t('guide_s1_t'),
              body: L.t('guide_s1_b'),
            ),
            _Step(
              n: 2,
              icon: sub ? Icons.public : Icons.telegram,
              title: sub ? L.t('guide_sub_s2_t') : L.t('guide_s2_t'),
              body: sub ? L.t('guide_sub_s2_b') : L.t('guide_s2_b'),
            ),
            _Step(
              n: 3,
              icon: Icons.workspace_premium,
              title: sub ? L.t('guide_sub_s3_t') : L.t('guide_s3_t'),
              body: sub ? L.t('guide_sub_s3_b') : L.t('guide_s3_b'),
            ),

            const SizedBox(height: 20),
            if (sub)
              _PrimaryButton(
                label: L.t('guide_ok_home'),
                icon: Icons.home_outlined,
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                ),
              )
            else ...[
              _PrimaryButton(
                label: L.t('guide_open_bot'),
                icon: Icons.open_in_new,
                onTap: () => launchUrl(Uri.parse(_botUrl),
                    mode: LaunchMode.externalApplication),
              ),
              const SizedBox(height: 10),
              _OutlineButton(
                label: L.t('guide_have_link'),
                icon: Icons.link,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ImportScreen(firstRun: true)),
                ),
              ),
              const SizedBox(height: 10),
              // Привязка подписки по Telegram ID — прямо из инструкции.
              _OutlineButton(
                label: L.t('guide_link_tg'),
                icon: Icons.telegram,
                onTap: () => showLinkTelegramDialog(context),
              ),
            ],

            if (afterFreeEnable && !sub) ...[
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: P.lime,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(L.t('guide_ok_home'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF0C1206),
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Верхний баннер-статус экрана-инструкции.
  Widget _banner(
      {required IconData icon, required String text, String? srvLine}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.lime.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.lime.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: P.lime),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: P.text, fontSize: 13.5)),
            ),
          ]),
          if (srvLine != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.dns_outlined, size: 15, color: P.limeText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(srvLine,
                    style: const TextStyle(color: P.limeText, fontSize: 12)),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final IconData icon;
  final String title;
  final String body;
  const _Step({
    required this.n,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: P.surfaceHi,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: P.limeText, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$n. $title',
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        color: P.textDim, fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: P.grad,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: P.lime.withValues(alpha: 0.38),
                blurRadius: 22,
                spreadRadius: -4,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF0C1206), size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF0C1206),
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlineButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: P.surfaceHi),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: P.textDim, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(color: P.text, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
