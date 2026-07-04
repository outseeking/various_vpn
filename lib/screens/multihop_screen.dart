/// Мультихоп («Двойной VPN»): трафик идёт через ДВЕ ноды — входную и выходную.
/// Входная видит твой реальный IP, но не сайты; выходная видит сайты, но не тебя.
/// Обе — наши серверы, цепочка строится на клиенте (Xray dialerProxy).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_server.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class MultihopScreen extends StatelessWidget {
  const MultihopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final servers = state.servers.where((s) => s.xraySupported).toList();
    final exit = state.activeServer; // выход = текущий выбранный сервер
    final entryId = state.relayServerId;

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: const Text('Двойной VPN (мультихоп)')),
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Максимум приватности',
                    style: TextStyle(
                        color: P.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                  'Трафик проходит через две ноды подряд: вход → выход. Входная '
                  'знает твой IP, но не видит сайты; выходная видит сайты, но не '
                  'знает, кто ты. Даже если одну ноду скомпрометируют — связать '
                  'тебя с трафиком не выйдет.',
                  style: TextStyle(color: P.textDim, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Честное, но красивое предупреждение о скорости.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: P.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: P.gold.withValues(alpha: 0.35)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.speed, color: P.gold, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Скорость будет ниже обычной — это нормально. Данные шифруются '
                    'дважды и проходят лишнюю страну, поэтому пинг растёт. Для '
                    'YouTube/игр лучше обычный режим; двойной — когда важна '
                    'максимальная анонимность.',
                    style: TextStyle(color: P.textDim, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: state.multihop,
            onChanged: state.setMultihop,
            title: const Text('Включить двойной VPN',
                style: TextStyle(color: P.text, fontWeight: FontWeight.w600)),
            activeThumbColor: P.limeText,
            contentPadding: EdgeInsets.zero,
          ),
          if (state.multihop) ...[
            const SizedBox(height: 8),
            _picker(
              context,
              title: '① Вход (через эту ноду заходишь)',
              servers: servers.where((s) => s.id != exit?.id).toList(),
              selectedId: entryId,
              onPick: (id) => state.setRelayServer(id),
              autoLabel: 'Авто (любая другая нода)',
              allowAuto: true,
            ),
            const SizedBox(height: 14),
            _picker(
              context,
              title: '② Выход (его страну видят сайты)',
              servers: servers.where((s) => s.id != entryId).toList(),
              selectedId: exit?.id,
              onPick: (id) {
                if (id != null) state.setManualServer(id);
              },
              allowAuto: false,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: P.grad,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Маршрут:  ${_name(state, entryId) ?? "авто"}  →  ${exit?.displayName ?? "выход"}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF0C1206),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _picker(
    BuildContext context, {
    required String title,
    required List<VpnServer> servers,
    required String? selectedId,
    required ValueChanged<String?> onPick,
    String autoLabel = '',
    required bool allowAuto,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(title,
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        if (allowAuto)
          RadioListTile<String?>(
            value: null,
            groupValue: selectedId,
            onChanged: onPick,
            title: Text(autoLabel, style: const TextStyle(color: P.text)),
            activeColor: P.limeText,
            contentPadding: EdgeInsets.zero,
          ),
        for (final s in servers)
          RadioListTile<String?>(
            value: s.id,
            groupValue: selectedId,
            onChanged: onPick,
            title: Text('${s.flag} ${s.displayName}',
                style: const TextStyle(color: P.text)),
            subtitle: s.pingMs > 0
                ? Text('${s.pingMs} ms',
                    style: const TextStyle(color: P.textFaint, fontSize: 12))
                : null,
            activeColor: P.limeText,
            contentPadding: EdgeInsets.zero,
          ),
      ],
    );
  }

  String? _name(AppState state, String? id) {
    if (id == null) return null;
    for (final s in state.servers) {
      if (s.id == id) return s.displayName;
    }
    return null;
  }
}
