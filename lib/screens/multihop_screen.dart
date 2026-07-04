/// Двойной VPN (мультихоп). ВХОД — сервер, к которому ты сейчас подключён
/// (выбирается на главном экране). ВЫХОД — выбираешь здесь, в списке. Трафик
/// идёт вход → выход → интернет. Обе ноды — наши, цепочка строится на клиенте.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class MultihopScreen extends StatelessWidget {
  const MultihopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entry = state.activeServer; // вход = текущий сервер
    final exitId = state.multihopExitId;
    final exits =
        state.servers.where((s) => s.xraySupported && s.id != entry?.id).toList();

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('mh_title'))),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('mh_privacy_title'),
                    style: const TextStyle(
                        color: P.text, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  L.t('mh_privacy_body'),
                  style: const TextStyle(color: P.textDim, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Живая карточка «вход» — какой сервер сейчас активен.
          _EntryCard(
            flag: entry?.flag ?? '🌐',
            name: entry?.displayName ?? L.t('mh_no_server'),
            connected: state.isConnected,
          ),
          const SizedBox(height: 14),

          // Честное предупреждение о скорости.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: P.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: P.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.speed, color: P.gold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    L.t('mh_speed'),
                    style: const TextStyle(color: P.textDim, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            value: state.multihop,
            onChanged: state.setMultihop,
            title: Text(L.t('mh_enable'),
                style: const TextStyle(color: P.text, fontWeight: FontWeight.w600)),
            activeThumbColor: P.limeText,
            contentPadding: EdgeInsets.zero,
          ),

          if (state.multihop) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(L.t('mh_exit_label'),
                  style: const TextStyle(
                      color: P.text, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            if (exits.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(L.t('mh_need_two'),
                    style: const TextStyle(color: P.textFaint)),
              ),
            for (final s in exits)
              RadioListTile<String?>(
                value: s.id,
                groupValue: exitId,
                onChanged: state.setMultihopExit,
                title: Text('${s.flag} ${s.displayName}',
                    style: const TextStyle(color: P.text)),
                subtitle: s.pingMs > 0
                    ? Text('${s.pingMs} ms',
                        style: const TextStyle(color: P.textFaint, fontSize: 12))
                    : null,
                activeColor: P.limeText,
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: P.grad,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${L.t('mh_route')}:  ${entry?.flag ?? "🌐"} ${entry?.displayName ?? ""}  →  '
                '${_exitLabel(state, exitId)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF0C1206),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L.t('mh_footer'),
              style: const TextStyle(color: P.textFaint, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  String _exitLabel(AppState state, String? id) {
    if (id == null) return L.t('mh_pick_exit');
    for (final s in state.servers) {
      if (s.id == id) return '${s.flag} ${s.displayName}';
    }
    return L.t('mh_pick_exit');
  }
}

/// Пульсирующая карточка текущего сервера-входа.
class _EntryCard extends StatefulWidget {
  final String flag;
  final String name;
  final bool connected;
  const _EntryCard(
      {required this.flag, required this.name, required this.connected});

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.limeText.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // пульсирующий индикатор «вход»
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value;
              return Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: P.lime.withValues(alpha: 0.12 + 0.10 * t),
                  boxShadow: [
                    BoxShadow(
                        color: P.lime.withValues(
                            alpha: (widget.connected ? 0.4 : 0.15) * t),
                        blurRadius: 8 + 10 * t,
                        spreadRadius: 1 + 2 * t),
                  ],
                ),
                child: Text(widget.flag, style: const TextStyle(fontSize: 22)),
              );
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('mh_entry_tag'),
                    style: const TextStyle(
                        color: P.limeText,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(widget.name,
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text(
                    widget.connected
                        ? L.t('mh_entry_on')
                        : L.t('mh_entry_off'),
                    style: const TextStyle(color: P.textFaint, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
