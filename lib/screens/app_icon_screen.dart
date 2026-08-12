/// Настройки → Иконка приложения. Шесть вариантов одного знака: щит с молнией
/// остаётся, меняется «оправа». Так иконка подстраивается под домашний экран
/// человека, но приложение остаётся узнаваемым.
///
/// Как это устроено: Android не умеет менять иконку на лету, поэтому в
/// манифесте лежит по одному activity-alias на вариант, а Kotlin-сторона
/// включает нужный и гасит остальные (см. MainActivity.applyIcon).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../services/home_widget_sync.dart';
import '../services/storage.dart';
import '../theme/app_palette.dart';
import '../theme/motion.dart';
import '../widgets/tap_scale.dart';
import '../widgets/app_toast.dart';

/// Ключ варианта → подпись. Ключи совпадают с алиасами в манифесте.
const _icons = <String, String>{
  'classic': 'icon_classic',
  'midnight': 'icon_midnight',
  'indigo': 'icon_indigo',
  'steel': 'icon_steel',
  'pearl': 'icon_pearl',
  'lime': 'icon_lime',
};

const _channel = MethodChannel('various_vpn/status');

class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  // Своё сохранённое значение — источник правды для галочки: опрос системы
  // сразу после переключения иногда ещё отдаёт прежний алиас.
  late String _current = Storage.instance.getStr('app_icon', def: 'classic');

  Future<void> _pick(String key) async {
    if (key == _current) return;
    setState(() => _current = key);
    Storage.instance.setStr('app_icon', key);
    final ok =
        await _channel.invokeMethod<bool>('setAppIcon', {'key': key}) ?? false;
    // Значок на домашнем виджете меняем сразу же — он часть того же набора.
    await HomeWidgetSync.refreshIcon(key);
    if (!mounted) return;
    if (ok) {
      AppToast.ok(context, L.t('icon_changed'));
    } else {
      AppToast.error(context, L.t('icon_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('app_icon'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(L.t('icon_intro'),
              style: const TextStyle(
                  color: P.textDim, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.78,
            children: [
              for (final e in _icons.entries)
                _IconTile(
                  slug: e.key,
                  label: L.t(e.value),
                  selected: _current == e.key,
                  onTap: () => _pick(e.key),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 15, color: P.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(L.t('icon_note'),
                  style: const TextStyle(
                      color: P.textFaint, fontSize: 11.5, height: 1.45)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final String slug;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _IconTile({
    required this.slug,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      haptic: true,
      scale: 0.94,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: M.state,
            curve: M.standard,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? P.lime : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: P.lime.withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: -4),
                    ]
                  : null,
            ),
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset('assets/icon/preview_$slug.png',
                    width: 74, height: 74, fit: BoxFit.cover),
              ),
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: P.lime, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        size: 13, color: P.onLime),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected ? P.limeText : P.textDim,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
