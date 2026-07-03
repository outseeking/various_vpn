/// Список серверов: поиск, сортировка (пинг/страна/избранное), избранные,
/// цветовой индикатор качества пинга и анимация измерения. Выбор сервера для
/// ручного режима. Тёмная тема.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vpn_server.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/flag.dart';

enum _Sort { ping, country, favorite }

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _query = '';
  _Sort _sort = _Sort.ping;

  List<VpnServer> _filtered(AppState s) {
    final q = _query.trim().toLowerCase();
    var list = s.servers.where((srv) {
      if (q.isEmpty) return true;
      return srv.title.toLowerCase().contains(q) ||
          srv.countryName.toLowerCase().contains(q) ||
          srv.address.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.ping:
        list.sort((a, b) {
          final pa = a.pingMs < 0 ? 1 << 30 : a.pingMs;
          final pb = b.pingMs < 0 ? 1 << 30 : b.pingMs;
          return pa.compareTo(pb);
        });
        break;
      case _Sort.country:
        list.sort((a, b) => a.countryName.compareTo(b.countryName));
        break;
      case _Sort.favorite:
        list.sort((a, b) {
          final fa = s.isFavorite(a.id) ? 0 : 1;
          final fb = s.isFavorite(b.id) ? 0 : 1;
          return fa.compareTo(fb);
        });
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = _filtered(state);
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        title: const Text('Серверы'),
        actions: [
          IconButton(
            tooltip: 'Пинговать все',
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
          ? const Center(
              child: Text('Нет серверов — импортируй подписку',
                  style: TextStyle(color: P.textFaint)))
          : Column(
              children: [
                // поиск
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: P.text),
                    decoration: InputDecoration(
                      hintText: 'Поиск страны или сервера',
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
                // сортировка
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    const Text('Сортировка:',
                        style: TextStyle(color: P.textFaint, fontSize: 12)),
                    const SizedBox(width: 8),
                    _sortChip('Пинг', _Sort.ping),
                    const SizedBox(width: 6),
                    _sortChip('Страна', _Sort.country),
                    const SizedBox(width: 6),
                    _sortChip('Избранное', _Sort.favorite),
                  ]),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final s = list[i];
                      final selected = state.activeServer?.id == s.id;
                      return _Row(
                        server: s,
                        selected: selected,
                        favorite: state.isFavorite(s.id),
                        measuring: state.busy && s.pingMs < 0,
                        onTap: () {
                          state.setManualServer(s.id);
                          if (state.mode != GlobalMode.manual) {
                            state.setMode(GlobalMode.manual);
                          }
                        },
                        onFav: () => state.toggleFavorite(s.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sortChip(String label, _Sort s) {
    final on = _sort == s;
    return GestureDetector(
      onTap: () => setState(() => _sort = s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? P.lime.withValues(alpha: 0.15) : P.surfaceLo,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? P.lime : P.surfaceHi),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? P.limeText : P.textFaint, fontSize: 12)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? P.lime.withValues(alpha: 0.08) : P.surfaceLo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? P.lime : P.surfaceHi, width: selected ? 1 : 0.5),
        ),
        child: Row(
          children: [
            CountryFlag(server.countryCode.isEmpty ? '??' : server.countryCode),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.title,
                      style: const TextStyle(color: P.text, fontSize: 14)),
                  // Протокол + транспорт (Reality/gRPC) — без IP/домена.
                  Text(server.transportLabel,
                      style: const TextStyle(color: P.textFaint, fontSize: 11)),
                ],
              ),
            ),
            // индикатор пинга
            if (measuring)
              const SizedBox(
                width: 13,
                height: 13,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: P.limeText),
              )
            else ...[
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: P.pingColor(server.pingMs)),
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
