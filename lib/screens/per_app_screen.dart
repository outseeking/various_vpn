/// Раздельное туннелирование (split tunneling) в стиле Quattro, в нашем тёмном
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
import '../widgets/tap_scale.dart';

class PerAppScreen extends StatefulWidget {
  const PerAppScreen({super.key});

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
      state.allPackages = apps.map((a) => a.packageName).toSet();
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: P.bg,
        appBar: AppBar(
          title: Text(L.t('tunneling')),
          bottom: TabBar(
            indicatorColor: P.lime,
            labelColor: P.limeText,
            unselectedLabelColor: P.textFaint,
            tabs: [
              Tab(text: L.t('tab_apps')),
              Tab(text: L.t('tab_urls')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _appsTab(context),
            const _UrlsTab(),
          ],
        ),
      ),
    );
  }

  Widget _appsTab(BuildContext context) {
    final state = context.watch<AppState>();
    final filtered = _query.isEmpty
        ? _apps
        : _apps
            .where((a) => a.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
        children: [
          // режим списка: Через VPN / В обход VPN
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ModeSelector(
              throughVpn: state.splitThroughVpn,
              onChanged: state.setSplitThroughVpn,
            ),
          ),
          // мастер-переключатель
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            title: Text(L.t('split_enable'),
                style: const TextStyle(color: P.text, fontSize: 15)),
            subtitle: Text(
              state.splitThroughVpn ? L.t('split_hint_through') : L.t('split_hint_bypass'),
              style: const TextStyle(color: P.textFaint, fontSize: 12),
            ),
            value: state.splitEnabled,
            activeThumbColor: P.lime,
            onChanged: state.setSplitEnabled,
          ),
          // поиск
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: P.text, fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: P.textFaint, size: 20),
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
                            onToggle: (v) =>
                                state.toggleSplitApp(app.packageName, v),
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

class _UrlsTab extends StatefulWidget {
  const _UrlsTab();
  @override
  State<_UrlsTab> createState() => _UrlsTabState();
}

class _UrlsTabState extends State<_UrlsTab> {
  final _ctrl = TextEditingController();

  // популярные RU-сайты, которые логично пускать мимо VPN
  static const _popular = [
    'gosuslugi.ru', 'sberbank.ru', 'tinkoff.ru', 'vtb.ru',
    'yandex.ru', 'vk.com', 'ok.ru', 'mail.ru', 'wildberries.ru',
    'ozon.ru', 'avito.ru', 'kinopoisk.ru', '2gis.ru',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final custom = state.splitUrls.where((u) => !_popular.contains(u)).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(L.t('url_hint'),
            style: const TextStyle(color: P.textFaint, fontSize: 12)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: P.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'example.com',
                hintStyle: const TextStyle(color: P.textFaint),
                isDense: true,
                filled: true,
                fillColor: P.surfaceLo,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) {
                state.addSplitUrl(v);
                _ctrl.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          TapScale(
            onTap: () {
              state.addSplitUrl(_ctrl.text);
              _ctrl.clear();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: P.lime,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, color: Color(0xFF0C1206)),
            ),
          ),
        ]),
        if (custom.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(L.t('url_your'),
              style: const TextStyle(color: P.textFaint, fontSize: 12)),
          const SizedBox(height: 8),
          ...custom.map((u) => _UrlRow(
                domain: u,
                on: true,
                onToggle: (v) => state.toggleSplitUrl(u, v),
              )),
        ],
        const SizedBox(height: 20),
        Text(L.t('url_popular'),
            style: const TextStyle(color: P.textFaint, fontSize: 12)),
        const SizedBox(height: 8),
        ..._popular.map((u) => _UrlRow(
              domain: u,
              on: state.splitUrls.contains(u),
              onToggle: (v) => state.toggleSplitUrl(u, v),
            )),
      ],
    );
  }
}

class _UrlRow extends StatelessWidget {
  final String domain;
  final bool on;
  final ValueChanged<bool> onToggle;
  const _UrlRow(
      {required this.domain, required this.on, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? P.lime : P.surfaceHi, width: on ? 1 : 0.5),
      ),
      child: Row(children: [
        const Icon(Icons.public, size: 18, color: P.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(domain,
              style: const TextStyle(color: P.text, fontSize: 14)),
        ),
        Switch(value: on, activeThumbColor: P.lime, onChanged: onToggle),
      ]),
    );
  }
}

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
          : const Icon(Icons.android, color: P.textFaint, size: 36),
      title: Text(app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: P.text, fontSize: 14)),
      trailing: Switch(
        value: selected,
        activeThumbColor: P.lime,
        onChanged: enabled ? onToggle : null,
      ),
    );
  }
}
