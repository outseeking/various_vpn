/// Статистика за всё время: суммарный трафик, топ стран, график по дням.
/// Данные накапливаются в AppState (пока на основе имитации скорости — станут
/// реальными, когда нативное ядро начнёт отдавать байты).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/flag.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  static String _bytes(int b) {
    if (b < 1024 * 1024) {
      return '${(b / 1024).toStringAsFixed(0)} ${L.t('unit_kb')}';
    }
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} ${L.t('unit_mb')}';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ${L.t('unit_gb')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final top = state.topCountries.take(5).toList();
    final days = state.last7Days;
    final maxDay = days.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('stats'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
                child: _Big(
                    label: L.t('st_total_down'),
                    value: _bytes(state.allTimeDown),
                    color: P.limeText)),
            const SizedBox(width: 12),
            Expanded(
                child: _Big(
                    label: L.t('st_total_up'),
                    value: _bytes(state.allTimeUp),
                    color: const Color(0xFFB48CE6))),
          ]),
          const SizedBox(height: 20),
          Text(L.t('st_last7'),
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            height: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: P.surfaceLo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: P.surfaceHi),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in days)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 70 * (d.value / maxDay).clamp(0.02, 1.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [P.lime, P.violet],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(d.key,
                            style: const TextStyle(
                                color: P.textFaint, fontSize: 9)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(L.t('st_fav'),
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (top.isEmpty)
            Text(L.t('st_nodata'),
                style: const TextStyle(color: P.textFaint, fontSize: 13))
          else
            ...top.map((e) {
              final topMax = top.first.value > 0 ? top.first.value : 1;
              final frac = e.value / topMax;
              final name = state.countryNameOf(e.key);
              final servers = state.serverStatsForCountry(e.key);
              return _CountryRow(
                cc: e.key,
                name: name,
                bytes: e.value,
                frac: frac.clamp(0.02, 1.0),
                serverCount: servers.length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CountryDetailScreen(cc: e.key, name: name),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Строка страны в списке любимых — тапабельная, ведёт в разбивку по серверам.
class _CountryRow extends StatelessWidget {
  final String cc;
  final String name;
  final int bytes;
  final double frac;
  final int serverCount;
  final VoidCallback onTap;
  const _CountryRow({
    required this.cc,
    required this.name,
    required this.bytes,
    required this.frac,
    required this.serverCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          CountryFlag(cc),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name,
                        style: const TextStyle(color: P.text, fontSize: 13)),
                    Text(StatsScreen._bytes(bytes),
                        style:
                            const TextStyle(color: P.textFaint, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 5,
                    backgroundColor: P.surfaceHi,
                    valueColor: const AlwaysStoppedAnimation(P.lime),
                  ),
                ),
                if (serverCount > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    L.t('st_servers_n', {'n': serverCount}),
                    style: const TextStyle(color: P.textFaint, fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: P.textFaint, size: 20),
        ]),
      ),
    );
  }
}

/// Разбивка трафика по конкретным серверам одной страны.
class CountryDetailScreen extends StatelessWidget {
  final String cc;
  final String name;
  const CountryDetailScreen({super.key, required this.cc, required this.name});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final servers = state.serverStatsForCountry(cc);
    final total = servers.fold<int>(0, (s, e) => s + e.value);
    final max =
        (servers.isEmpty || servers.first.value <= 0) ? 1 : servers.first.value;

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        title: Row(children: [
          CountryFlag(cc),
          const SizedBox(width: 10),
          Text(name),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // сводка по стране
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: P.grad,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Icon(Icons.public, color: P.onLime),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(L.t('st_country_total'),
                        style:
                            const TextStyle(color: P.onLimeDim, fontSize: 12)),
                    Text(StatsScreen._bytes(total),
                        style: const TextStyle(
                            color: P.onLime,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Text(L.t('st_servers_n', {'n': servers.length}),
                  style: const TextStyle(
                      color: P.onLimeDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 20),
          Text(L.t('st_by_server'),
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (servers.isEmpty)
            Text(L.t('st_nodata'),
                style: const TextStyle(color: P.textFaint, fontSize: 13))
          else
            ...servers.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final up = state.serverUpForCountry(cc, e.key);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: P.surfaceLo,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: P.surfaceHi),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: P.lime.withValues(alpha: 0.14),
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: P.limeText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: P.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (e.value / max).clamp(0.02, 1.0),
                        minHeight: 6,
                        backgroundColor: P.surfaceHi,
                        valueColor: const AlwaysStoppedAnimation(P.lime),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('↓ ${StatsScreen._bytes(e.value)}',
                            style: const TextStyle(
                                color: P.limeText, fontSize: 12.5)),
                        Text('↑ ${StatsScreen._bytes(up)}',
                            style: const TextStyle(
                                color: Color(0xFFB48CE6), fontSize: 12.5)),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Big({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.surfaceHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: P.textFaint, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
