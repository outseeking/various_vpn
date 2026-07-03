/// Настройки → Сеть и протокол: выбор IPv4/IPv6, свой DNS, фрагментация TLS.
/// Все опции применяются к Xray-конфигу при следующем подключении (или сразу —
/// если VPN активен, туннель переподнимется на лету).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/xray_config.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  late final TextEditingController _dnsCtrl;

  @override
  void initState() {
    super.initState();
    _dnsCtrl = TextEditingController(text: context.read<AppState>().customDns);
  }

  @override
  void dispose() {
    _dnsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('net_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Label(L.t('ip_type')),
          const SizedBox(height: 8),
          Row(
            children: IpStrategy.values.map((s) {
              final on = state.ipStrategy == s;
              return Expanded(
                child: GestureDetector(
                  onTap: () => state.setIpStrategy(s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: on ? P.lime.withValues(alpha: 0.1) : P.surfaceLo,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: on ? P.lime : P.surfaceHi,
                          width: on ? 1 : 0.5),
                    ),
                    child: Text(s.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: on ? P.limeText : P.textFaint,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            L.t('ip_type_hint'),
            style: const TextStyle(color: P.textFaint, fontSize: 11),
          ),
          const SizedBox(height: 24),

          _Label(L.t('custom_dns')),
          const SizedBox(height: 8),
          TextField(
            controller: _dnsCtrl,
            style: const TextStyle(color: P.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: '1.1.1.1, 8.8.8.8',
              hintStyle: const TextStyle(color: P.textFaint),
              filled: true,
              fillColor: P.surfaceLo,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: state.setCustomDns,
            onEditingComplete: () => state.setCustomDns(_dnsCtrl.text),
          ),
          const SizedBox(height: 6),
          Text(
            L.t('custom_dns_hint'),
            style: const TextStyle(color: P.textFaint, fontSize: 11),
          ),
          const SizedBox(height: 24),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L.t('fragment'),
                style: const TextStyle(color: P.text, fontSize: 14)),
            subtitle: Text(L.t('fragment_d'),
                style: const TextStyle(color: P.textFaint, fontSize: 12)),
            value: state.fragment,
            activeThumbColor: P.lime,
            onChanged: state.setFragment,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: P.textFaint, fontSize: 12));
}
