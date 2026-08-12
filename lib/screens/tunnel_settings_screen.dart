/// Настройки → Туннель. Всё про то, ЧТО и КУДА идёт внутри соединения:
/// маршрутизация, фильтры, сеть и протокол, замер скорости связи, свои серверы.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/settings_kit.dart';
import 'per_app_screen.dart' show showFreeLockedDialog;
import 'custom_servers_screen.dart';
import 'network_settings_screen.dart';
import 'ping_settings_screen.dart';

class TunnelSettingsScreen extends StatelessWidget {
  const TunnelSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Замки — по ВОЗМОЖНОСТЯМ, а не по нашей подписке: со своей подпиской
    // другого сервиса настройки туннеля тоже должны работать.
    final free = !state.featuresUnlocked;
    void locked() => showFreeLockedDialog(context);

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('sec_tunnel'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SettingsHeader(L.t('tun_grp_routing')),
          SettingsGroup(children: [
            SettingsSwitch(
              icon: Icons.alt_route_rounded,
              title: L.t('bypass_ru'),
              subtitle: L.t('bypass_ru_d'),
              value: state.bypassRu,
              onChanged: state.setBypassRu,
              locked: free,
              onLockedTap: locked,
            ),
            SettingsSwitch(
              icon: Icons.smart_toy_outlined,
              tint: P.violetSoft,
              title: L.t('smart_ai'),
              subtitle: L.t('smart_ai_d'),
              value: state.smartAi,
              onChanged: state.setSmartAi,
              locked: free,
              onLockedTap: locked,
            ),
            SettingsSwitch(
              icon: Icons.block_rounded,
              tint: P.danger,
              title: L.t('adblock'),
              subtitle: L.t('adblock_d'),
              value: state.adBlock,
              onChanged: state.setAdBlock,
              locked: free,
              onLockedTap: locked,
            ),
          ]),
          SettingsHeader(L.t('tun_grp_speed')),
          SettingsGroup(children: [
            SettingsSwitch(
              icon: Icons.merge_type_rounded,
              tint: P.gold,
              title: L.t('mux'),
              subtitle: L.t('mux_d'),
              value: state.mux,
              onChanged: state.setMux,
              locked: free,
              onLockedTap: locked,
            ),
            SettingsSwitch(
              icon: Icons.home_outlined,
              title: L.t('lan_direct'),
              subtitle: L.t('lan_direct_d'),
              value: state.lanDirect,
              onChanged: state.setLanDirect,
              locked: free,
              onLockedTap: locked,
            ),
          ]),
          SettingsHeader(L.t('tun_grp_net')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.lan_outlined,
              title: L.t('net_settings'),
              subtitle: L.t('net_settings_d'),
              value: state.ipStrategy.label,
              locked: free,
              onTap: free
                  ? locked
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const NetworkSettingsScreen())),
            ),
            SettingsRow(
              icon: Icons.speed_outlined,
              tint: P.gold,
              title: L.t('ping_label'),
              subtitle: L.t('ping_label_d'),
              // Методов теперь пять, а подпись знала только два и на всём
              // остальном врала «TCP». Берём короткое имя выбранного.
              value: L.t('ping_short_${state.pingType}'),
              locked: free,
              onTap: free
                  ? locked
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PingSettingsScreen())),
            ),
          ]),
          SettingsHeader(L.t('tun_grp_own')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.dns_outlined,
              tint: P.violetSoft,
              title: L.t('cs_nav'),
              subtitle: L.t('cs_nav_d'),
              locked: free,
              onTap: free
                  ? locked
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const CustomServersScreen())),
            ),
          ]),
        ],
      ),
    );
  }
}
