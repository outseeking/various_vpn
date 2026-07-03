/// Настройки → Пинг: тип замера (via Proxy — точный, через Xray;
/// TCP — быстрый хендшейк) и тестовый URL для проверки via Proxy.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class PingSettingsScreen extends StatefulWidget {
  const PingSettingsScreen({super.key});

  @override
  State<PingSettingsScreen> createState() => _PingSettingsScreenState();
}

class _PingSettingsScreenState extends State<PingSettingsScreen> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _urlCtrl = TextEditingController(text: s.pingTestUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

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
            title: 'via Proxy',
            subtitle: L.t('ping_proxy_d'),
            selected: state.pingType == 'proxy',
            onTap: () => state.pingType = 'proxy',
          ),
          _OptionTile(
            title: 'TCP',
            subtitle: L.t('ping_tcp_d'),
            selected: state.pingType == 'tcp',
            onTap: () => state.pingType = 'tcp',
          ),
          if (state.pingType == 'proxy') ...[
            const SizedBox(height: 20),
            Text(L.t('ping_test_url'),
                style: const TextStyle(color: P.textFaint, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: P.text, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: P.surfaceLo,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) => state.pingTestUrl = v,
              onEditingComplete: () => state.pingTestUrl = _urlCtrl.text,
            ),
          ],
        ],
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
              color: selected ? P.lime : P.surfaceHi, width: selected ? 1 : 0.5),
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
                  Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
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
