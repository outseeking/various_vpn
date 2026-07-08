/// Инструкция «как подключиться» — показывается после включения бесплатного
/// Telegram-VPN (для тех, кто только скачал приложение из стора). Объясняет, что
/// сейчас работает, как разрешить VPN и как получить полный доступ.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../theme/app_palette.dart';
import 'home_screen.dart';
import 'import_screen.dart';

const _botUrl = 'https://t.me/variousvpnbot';

class ConnectGuideScreen extends StatelessWidget {
  /// true — пришли после включения бесплатного режима (другой заголовок/кнопка).
  final bool afterFreeEnable;
  const ConnectGuideScreen({super.key, this.afterFreeEnable = false});

  @override
  Widget build(BuildContext context) {
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
            if (afterFreeEnable)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: P.lime.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: P.lime.withValues(alpha: 0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: P.lime),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Бесплатный VPN для Telegram включён. Telegram работает '
                      'через VPN, остальные приложения — напрямую.',
                      style: TextStyle(color: P.text, fontSize: 13.5),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 18),
            Text('Что дальше',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: P.text, fontSize: 20)),
            const SizedBox(height: 16),

            const _Step(
              n: 1,
              icon: Icons.vpn_key,
              title: 'Разреши VPN-профиль',
              body: 'При первом включении система спросит разрешение на VPN — '
                  'нажми «Разрешить». Это нужно, чтобы трафик шёл через туннель.',
            ),
            const _Step(
              n: 2,
              icon: Icons.telegram,
              title: 'Сейчас работает только Telegram',
              body: 'В бесплатном режиме через VPN идёт лишь Telegram. Открой '
                  'Telegram — он будет работать даже при блокировках.',
            ),
            const _Step(
              n: 3,
              icon: Icons.workspace_premium,
              title: 'Хочешь весь интернет?',
              body: 'Возьми подписку в нашем Telegram-боте и вставь ссылку — '
                  'тогда VPN заработает для всех приложений с авто-выбором '
                  'лучшего сервера.',
            ),

            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Открыть бота и взять подписку',
              icon: Icons.open_in_new,
              onTap: () => launchUrl(Uri.parse(_botUrl),
                  mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 10),
            _OutlineButton(
              label: 'У меня есть ссылка подписки',
              icon: Icons.link,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ImportScreen(firstRun: true)),
              ),
            ),

            if (afterFreeEnable) ...[
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: P.lime,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('Понятно, на главный',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: P.grad,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF0C1206), size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF0C1206),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
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
