/// Авто-VPN в незнакомых сетях. Включатель + список доверенных Wi-Fi (в них VPN
/// не поднимается сам). В стиле приложения (тёмная тема, лаймовый акцент).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/app_toast.dart';
import '../widgets/ios_switch.dart';

class AutoWifiScreen extends StatelessWidget {
  const AutoWifiScreen({super.key});

  Future<void> _addCurrent(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    // Чтение SSID требует доступа к геолокации — запрашиваем перед чтением.
    final granted = await state.ensureWifiPermission();
    if (!context.mounted) return;
    if (!granted) {
      AppToast.error(context, L.t('awifi_perm'));
      return;
    }
    final ssid = await state.currentWifiSsid();
    if (!context.mounted) return;
    if (ssid == null || ssid.isEmpty) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: P.surface,
        content: Text(L.t('awifi_no_ssid')),
      ));
      return;
    }
    // Просто добавляем — список ниже обновится сам (без всплывающей плашки).
    state.addTrustedSsid(ssid);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trusted = state.trustedSsids.toList()..sort();

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('awifi_title'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // главный переключатель + пояснение
          Container(
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
                    const Icon(Icons.wifi_lock, color: P.limeText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(L.t('awifi_enable'),
                          style: const TextStyle(
                              color: P.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                    IosSwitch(value: state.autoWifiProtect,
                      onChanged: (v) async {
                        final ok = await state.setAutoWifiProtect(v);
                        if (!context.mounted) return;
                        if (v && !ok) {
                          AppToast.error(context, L.t('awifi_perm'));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(L.t('awifi_enable_d'),
                    style: const TextStyle(
                        color: P.textDim, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Инструкция: что нужно включить и почему.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: P.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: P.gold.withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline, color: P.gold, size: 20),
                  const SizedBox(width: 8),
                  Text(L.t('awifi_how_t'),
                      style: const TextStyle(
                          color: P.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                Text(L.t('awifi_how'),
                    style: const TextStyle(
                        color: P.textDim, fontSize: 13, height: 1.55)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(L.t('awifi_trusted'),
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(L.t('awifi_trusted_d'),
              style: const TextStyle(color: P.textFaint, fontSize: 12.5)),
          const SizedBox(height: 12),

          if (trusted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(L.t('awifi_none'),
                  style: const TextStyle(color: P.textFaint, fontSize: 13)),
            )
          else
            ...trusted.map((ssid) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: P.surfaceLo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: P.surfaceHi),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.wifi, color: P.limeText),
                    title: Text(ssid,
                        style: const TextStyle(color: P.text, fontSize: 14)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: P.textFaint),
                      onPressed: () => state.removeTrustedSsid(ssid),
                    ),
                  ),
                )),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: P.limeText,
                side: const BorderSide(color: P.surfaceHi),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.add_location_alt_outlined, size: 20),
              label: Text(L.t('awifi_add_current')),
              onPressed: () => _addCurrent(context),
            ),
          ),
        ],
      ),
    );
  }
}
