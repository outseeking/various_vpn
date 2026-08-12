/// Настройки → Пинг: тип замера (точный — через ядро; быстрый — рукопожатие
/// TCP), частота авто-замера и адрес, до которого меряем.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/xray_config.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class PingSettingsScreen extends StatelessWidget {
  const PingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('ping_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(L.t('ping_type'),
              style: const TextStyle(color: P.textFaint, fontSize: 12)),
          const SizedBox(height: 8),
          _OptionTile(
            title: L.t('ping_m_tcp'),
            subtitle: L.t('ping_tcp_d'),
            selected: state.pingType == 'tcp',
            onTap: () => state.pingType = 'tcp',
          ),
          _OptionTile(
            title: L.t('ping_m_tls'),
            subtitle: L.t('ping_proxy_d'),
            selected: state.pingType == 'proxy',
            onTap: () => state.pingType = 'proxy',
          ),
          const SizedBox(height: 22),
          Text(L.t('ping_every'),
              style: const TextStyle(color: P.textFaint, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // 15 секунд убрано: полный проход сам занимает несколько секунд,
              // и на таком интервале приложение почти всё время меряет.
              for (final s in const [0, 30, 60, 120, 300])
                _Chip(
                  label: _intervalLabel(s),
                  selected: state.pingEveryS == s,
                  onTap: () => state.pingEveryS = s,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(L.t('ping_every_hint'),
              style: const TextStyle(
                  color: P.textFaint, fontSize: 11.5, height: 1.4)),

          // Адрес виден ВСЕГДА: при включённом VPN им пользуется и быстрый
          // метод (обычный сокет там померял бы не сервер).
          const SizedBox(height: 22),
          Text(L.t('ping_test_url'),
              style: const TextStyle(color: P.textFaint, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Готовые точки вместо поля ввода: опечатка в адресе молча
              // ломала все замеры, а подобрать подходящий адрес человеку
              // неоткуда.
              for (final (name, url) in kProbeUrls)
                _Chip(
                  label: name,
                  selected: state.pingTestUrl == url,
                  onTap: () => state.pingTestUrl = url,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(L.t('ping_url_hint'),
              style: const TextStyle(
                  color: P.textFaint, fontSize: 11.5, height: 1.4)),
        ],
      ),
    );
  }

  static String _intervalLabel(int seconds) {
    if (seconds == 0) return L.t('ping_every_off');
    if (seconds < 60) return '$seconds ${L.t('unit_sec')}';
    return '${seconds ~/ 60} ${L.t('unit_min')}';
  }
}

/// Кнопка выбора одного значения из ряда: интервал замера или адрес проверки.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? P.lime.withValues(alpha: 0.15) : P.surfaceLo,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: selected ? P.lime : P.surfaceHi),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? P.limeText : P.textDim,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: P.surfaceLo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? P.lime : P.surfaceHi,
              width: selected ? 1 : 0.5),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? P.lime : P.textFaint,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: P.text, fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(color: P.textFaint, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
