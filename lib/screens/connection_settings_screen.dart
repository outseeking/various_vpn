/// Настройки → Подключение: когда поднимается туннель и что делать при обрыве.
///
/// Раздельное туннелирование живёт в своём разделе — дублировать его здесь
/// незачем.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/settings_kit.dart';
import 'killswitch_guide_screen.dart';
import '../platform.dart';
import 'per_app_screen.dart' show showFreeLockedDialog;

class ConnectionSettingsScreen extends StatelessWidget {
  const ConnectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Замки — по ВОЗМОЖНОСТЯМ, а не по нашей подписке (см. featuresUnlocked).
    final free = !state.featuresUnlocked;
    void locked() => showFreeLockedDialog(context);

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('sec_connection'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SettingsHeader(L.t('conn_grp_start')),
          SettingsGroup(children: [
            SettingsSwitch(
              icon: Icons.bolt,
              title: L.t('autoconnect'),
              subtitle: L.t('autoconnect_d'),
              value: state.autoConnect,
              onChanged: state.setAutoConnect,
              locked: free,
              onLockedTap: locked,
            ),
            SettingsSwitch(
              icon: Icons.autorenew_rounded,
              title: L.t('ondemand'),
              subtitle: L.t('ondemand_d'),
              value: state.onDemand,
              onChanged: state.setOnDemand,
              locked: free,
              onLockedTap: locked,
            ),
          ]),
          SettingsHeader(L.t('conn_grp_safety')),
          SettingsGroup(children: [
            // Самая частая причина обрывов «на ровном месте» — не сеть и не
            // сервер, а сама прошивка: Honor, Huawei и Xiaomi выгружают
            // фоновые сервисы. Даём это починить в один тап.
            const _BatteryRow(),
            // Kill switch на iOS настраивается не в системных настройках, а
            // правилами «по требованию» внутри профиля VPN — вести туда
            // человека нельзя, такого экрана там просто нет.
            if (Caps.systemVpnSettings)
              SettingsRow(
              icon: Icons.gpp_maybe_outlined,
              tint: P.danger,
              title: L.t('ks_nav'),
              subtitle: L.t('ks_nav_d'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const KillSwitchGuideScreen())),
            ),
          ]),
        ],
      ),
    );
  }
}


/// «Не выключать в фоне» — исключение из экономии батареи.
///
/// Показывает реальное состояние разрешения и по нажатию открывает системный
/// запрос. Когда разрешение уже выдано, строка спокойная и ни к чему не
/// призывает: чинить нечего.
class _BatteryRow extends StatefulWidget {
  const _BatteryRow();

  @override
  State<_BatteryRow> createState() => _BatteryRowState();
}

class _BatteryRowState extends State<_BatteryRow> with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Человек ушёл в системные настройки и вернулся — перечитываем статус,
    // иначе строка врала бы до перезахода на экран.
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    try {
      final ok = await Permission.ignoreBatteryOptimizations.isGranted;
      if (mounted) setState(() => _granted = ok);
    } catch (_) {
      if (mounted) setState(() => _granted = null);
    }
  }

  Future<void> _ask() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      // прошивка без такого экрана — просто ничего не произойдёт
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _granted == true;
    return SettingsRow(
      icon: ok ? Icons.battery_charging_full : Icons.battery_alert_outlined,
      tint: ok ? P.lime : P.gold,
      title: L.t('bg_keep'),
      subtitle: ok ? L.t('bg_keep_on') : L.t('bg_keep_off'),
      value: ok ? L.t('bg_keep_ok') : null,
      chevron: !ok,
      // Разрешение уже выдано — строка становится просто информационной,
      // но остаётся живой: по нажатию перепроверяем статус.
      onTap: () => ok ? _check() : _ask(),
    );
  }
}
