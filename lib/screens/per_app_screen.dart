/// Раздельное туннелирование (split tunneling) в нашем тёмном
/// раскрасе. Мастер-переключатель + режим «Через VPN / В обход VPN» + список
/// установленных приложений с тумблерами. Выбор реально влияет на маршрут:
/// AppState.blockedApps → flutter_v2ray blockedApps.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/paywall_sheet.dart';
import '../widgets/tap_scale.dart';
import '../widgets/ios_switch.dart';

/// «Нужна подписка». Раньше это был системный AlertDialog с одной кнопкой;
/// теперь — нормальная шторка-оффер (см. paywall_sheet.dart). Имя функции
/// сохранено: её зовут из десятка мест по всему приложению.
void showFreeLockedDialog(BuildContext context) => showPaywallSheet(context);

class PerAppScreen extends StatefulWidget {
  /// true — экран показан как вкладка в общей оболочке (без стрелки «назад»).
  final bool inShell;
  const PerAppScreen({super.key, this.inShell = false});

  @override
  State<PerAppScreen> createState() => _PerAppScreenState();
}

class _PerAppScreenState extends State<PerAppScreen> {
  List<AppInfo> _apps = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      setState(() => _loading = false);
      return;
    }
    try {
      final apps = await InstalledApps.getInstalledApps(true, true, '');
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      // сохраняем полный список пакетов в состояние (нужно для режима «Через VPN»)
      final state = context.read<AppState>();
      state.setAllPackages(apps.map((a) => a.packageName).toSet());
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.inShell,
        title: Text(L.t('tunneling')),
      ),
      body: _appsTab(context),
    );
  }

  Widget _appsTab(BuildContext context) {
    final state = context.watch<AppState>();
    final filtered = _query.isEmpty
        ? _apps
        : _apps
            .where((a) => a.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Раздельное туннелирование работает на любом сервере, в том числе на
    // сервере чужой подписки, — запирать его незачем.
    final free = !state.featuresUnlocked;
    return Column(
      children: [
        // В бесплатном режиме VPN идёт ТОЛЬКО для Telegram — правила зафиксированы.
        if (free)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: P.lime.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: P.lime.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.telegram, color: P.limeText),
              const SizedBox(width: 10),
              Expanded(
                child: Text(L.t('free_rules_banner'),
                    style: const TextStyle(color: P.text, fontSize: 13)),
              ),
              TextButton(
                onPressed: () => showFreeLockedDialog(context),
                child: Text(L.t('free_locked_buy')),
              ),
            ]),
          ),
        // режим списка: Через VPN / В обход VPN
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _ModeSelector(
            throughVpn: state.splitThroughVpn,
            onChanged: free
                ? (_) => showFreeLockedDialog(context)
                : state.setSplitThroughVpn,
          ),
        ),
        // мастер-переключатель
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18),
          title: Text(L.t('split_enable'),
              style: const TextStyle(color: P.text, fontSize: 15)),
          subtitle: Text(
            free
                ? L.t('free_rules_locked')
                : (state.splitThroughVpn
                    ? L.t('split_hint_through')
                    : L.t('split_hint_bypass')),
            style: const TextStyle(color: P.textFaint, fontSize: 12),
          ),
          value: free ? true : state.splitEnabled,
          onChanged: free
              ? (_) => showFreeLockedDialog(context)
              : state.setSplitEnabled,
        ),
        // поиск
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: P.text, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.search, color: P.textFaint, size: 20),
              hintText: L.t('search'),
              hintStyle: const TextStyle(color: P.textFaint),
              isDense: true,
              filled: true,
              fillColor: P.surfaceLo,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: P.limeText))
              : _apps.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(L.t('split_no_apps'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: P.textFaint)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final app = filtered[i];
                        final on = state.splitApps.contains(app.packageName);
                        return _AppRow(
                          app: app,
                          selected: on,
                          enabled: true,
                          onToggle: (v) => free
                              ? showFreeLockedDialog(context)
                              : state.toggleSplitApp(app.packageName, v),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final bool throughVpn;
  final ValueChanged<bool> onChanged;
  const _ModeSelector({required this.throughVpn, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(bool val, String title, String sub) {
      final on = throughVpn == val;
      return Expanded(
        child: TapScale(
          onTap: () => onChanged(val),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: on ? P.lime.withValues(alpha: 0.1) : P.surfaceLo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: on ? P.lime : P.surfaceHi, width: on ? 1 : 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: on ? P.limeText : P.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(color: P.textFaint, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      seg(false, L.t('split_bypass'), L.t('split_bypass_sub')),
      const SizedBox(width: 8),
      seg(true, L.t('split_through'), L.t('split_through_sub')),
    ]);
  }
}

// ---- вкладка URL: сайты в обход VPN (идут напрямую) ----

class _AppRow extends StatelessWidget {
  final AppInfo app;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  const _AppRow({
    required this.app,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final Uint8List? icon = app.icon;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: icon != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(icon, width: 36, height: 36))
          // Часть приложений иконку не отдаёт. Серый робот на всех таких
          // строках выглядел как ошибка загрузки; плитка с буквой читается
          // как осмысленная заглушка и помогает найти нужное приложение.
          : _LetterIcon(name: app.name, id: app.packageName),
      title: Text(app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: P.text, fontSize: 14)),
      trailing: IosSwitch(value: selected,
        onChanged: enabled ? onToggle : null,
      ),
    );
  }
}

/// Заглушка вместо иконки приложения: плитка с первой буквой имени.
/// Цвет выводится из идентификатора пакета — у каждого приложения он свой и
/// не меняется от запуска к запуску.
class _LetterIcon extends StatelessWidget {
  final String name;
  final String id;
  const _LetterIcon({required this.name, required this.id});

  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xFF3E5C8A),
      Color(0xFF6B4A8A),
      Color(0xFF2F6B5E),
      Color(0xFF8A5A3E),
      Color(0xFF4A5C6B),
      Color(0xFF6B4A5C),
    ];
    final tint = palette[id.hashCode.abs() % palette.length];
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(letter,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}
