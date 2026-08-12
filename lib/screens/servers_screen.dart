/// Список серверов: поиск, избранные, цветовой индикатор качества пинга и
/// анимация измерения. Выбор сервера для ручного режима. Тёмная тема.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_server.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../theme/motion.dart';
import '../widgets/tap_scale.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/flag.dart';
import 'per_app_screen.dart' show showFreeLockedDialog;

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _query = '';

  /// Только поиск. Сортировку убрали намеренно: порядок конфигов человек
  /// задаёт сам перетаскиванием на главной, и вторая, независимая раскладка на
  /// этом экране означала, что один и тот же список выглядит по-разному в двух
  /// местах — а отметка выбранного сервера каждый раз оказывалась «не там».
  List<VpnServer> _filtered(AppState s) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return s.servers;
    return s.servers.where((srv) {
      return srv.title.toLowerCase().contains(q) ||
          srv.countryName.toLowerCase().contains(q) ||
          srv.address.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = _filtered(state);
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        title: Text(L.t('servers')),
        actions: [
          IconButton(
            tooltip: L.t('srv_ping_all'),
            icon: state.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: P.limeText))
                : const Icon(Icons.radar, color: P.limeText),
            onPressed: state.busy ? null : state.pingAll,
          ),
        ],
      ),
      body: state.servers.isEmpty
          ? Center(
              child: Text(L.t('srv_none'),
                  style: const TextStyle(color: P.textFaint)))
          : Column(
              children: [
                // поиск
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: P.text),
                    decoration: InputDecoration(
                      hintText: L.t('srv_search'),
                      hintStyle: const TextStyle(color: P.textFaint),
                      prefixIcon: const Icon(Icons.search, color: P.textFaint),
                      filled: true,
                      fillColor: P.surfaceLo,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final s = list[i];
                      final selected = state.activeServer?.id == s.id;
                      return FadeSlideIn(
                        index: i,
                        child: _Row(
                          server: s,
                          selected: selected,
                          favorite: state.isFavorite(s.id),
                          measuring: state.busy && s.pingMs < 0,
                          onTap: () {
                            // ЗАЩИТА: без активной подписки НАШИ серверы не
                            // выбираются — ведём на оформление. Серверы своей
                            // (чужой) подписки выбирать можно: за них человек
                            // уже заплатил другому сервису.
                            if (!state.hasAccess && !s.foreign) {
                              showFreeLockedDialog(context);
                              return;
                            }
                            state.setManualServer(s.id);
                            if (state.mode != GlobalMode.manual) {
                              state.setMode(GlobalMode.manual);
                            }
                          },
                          onFav: () => state.toggleFavorite(s.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

}

class _Row extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final bool favorite;
  final bool measuring;
  final VoidCallback onTap;
  final VoidCallback onFav;
  const _Row({
    required this.server,
    required this.selected,
    required this.favorite,
    required this.measuring,
    required this.onTap,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      scale: 0.985,
      child: AnimatedContainer(
        duration: M.state,
        curve: M.standard,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? P.lime.withValues(alpha: 0.08) : P.surfaceLo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? P.lime : P.surfaceHi,
              width: selected ? 1 : 0.5),
        ),
        child: Row(
          children: [
            CountryFlag(server.countryCode.isEmpty ? '??' : server.countryCode),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(server.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: P.text, fontSize: 14)),
                    ),
                    // Сервер из ЧУЖОЙ подписки помечаем: иначе непонятно, чей
                    // он и почему работает без нашей оплаты.
                    if (server.foreign) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: P.violetSoft.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: P.violetSoft.withValues(alpha: 0.35)),
                        ),
                        child: Text(L.t('srv_own'),
                            style: const TextStyle(
                                color: P.violetSoft,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  // Протокол + транспорт (Reality/gRPC) — без IP/домена.
                  // Если сервер проверкой признан нерабочим, говорим об этом
                  // прямо: пинг до него может проходить, и без пометки человек
                  // выбирает его снова и снова.
                  Text(
                      server.unreachable
                          ? L.t('srv_dead')
                          : server.transportLabel,
                      style: TextStyle(
                          color: server.unreachable ? P.danger : P.textFaint,
                          fontSize: 11)),
                ],
              ),
            ),
            // индикатор пинга
            if (measuring)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: P.limeText),
              )
            else ...[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: P.pingColor(server.pingMs,
                        proxy: server.pingVia == 'proxy')),
              ),
              Text(server.pingMs < 0 ? '—' : '${server.pingMs} ms',
                  style: const TextStyle(color: P.textDim, fontSize: 12)),
            ],
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(favorite ? Icons.star : Icons.star_border,
                  color: favorite ? P.gold : P.textFaint, size: 20),
              onPressed: onFav,
            ),
            if (selected)
              const Icon(Icons.check_circle, color: P.lime, size: 18),
          ],
        ),
      ),
    );
  }
}
