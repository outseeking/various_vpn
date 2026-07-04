/// Гид по «настоящему» Kill-switch: системная функция Android «Always-on VPN +
/// блокировать соединения без VPN». В отличие от app-level логики, она работает
/// на уровне ОС и не пропускает трафик даже при краше приложения/нехватке памяти.
library;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme/app_palette.dart';

class KillSwitchGuideScreen extends StatelessWidget {
  const KillSwitchGuideScreen({super.key});

  Future<void> _openVpnSettings() async {
    // Открывает системный экран VPN, где включается Always-on + блокировка.
    const intent = AndroidIntent(action: 'android.settings.VPN_SETTINGS');
    try {
      await intent.launch();
    } catch (_) {
      const fallback = AndroidIntent(action: 'android.settings.SETTINGS');
      try {
        await fallback.launch();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('ks_title'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: P.surfaceLo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: P.surfaceHi),
            ),
            child: Text(
              L.t('ks_intro'),
              style: const TextStyle(color: P.textDim, fontSize: 14, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          Text(L.t('ks_how'),
              style: const TextStyle(
                  color: P.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _step(1, L.t('ks_s1')),
          _step(2, L.t('ks_s2')),
          _step(3, L.t('ks_s3')),
          _step(4, L.t('ks_s4')),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openVpnSettings,
            icon: const Icon(Icons.open_in_new),
            label: Text(L.t('ks_open')),
          ),
          const SizedBox(height: 12),
          Text(
            L.t('ks_hint'),
            style: const TextStyle(color: P.textFaint, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _step(int n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  gradient: P.grad, shape: BoxShape.circle),
              child: Text('$n',
                  style: const TextStyle(
                      color: Color(0xFF0C1206),
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text,
                    style: const TextStyle(
                        color: P.text, fontSize: 14, height: 1.4)),
              ),
            ),
          ],
        ),
      );
}
