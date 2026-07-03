/// Статистика за всё время: суммарный трафик, топ стран, график по дням.
/// Данные накапливаются в AppState (пока на основе имитации скорости — станут
/// реальными, когда нативное ядро начнёт отдавать байты).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/flag.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  static String _bytes(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
    }
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final top = state.topCountries.take(5).toList();
    final days = state.last7Days;
    final maxDay = days.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: const Text('Статистика')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
                child: _Big(
                    label: 'Всего скачано',
                    value: _bytes(state.allTimeDown),
                    color: P.limeText)),
            const SizedBox(width: 12),
            Expanded(
                child: _Big(
                    label: 'Всего отдано',
                    value: _bytes(state.allTimeUp),
                    color: const Color(0xFFB48CE6))),
          ]),
          const SizedBox(height: 20),

          const Text('За последние 7 дней',
              style: TextStyle(
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

          const Text('Любимые страны',
              style: TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (top.isEmpty)
            const Text('Пока нет данных — подключись, и здесь появится статистика.',
                style: TextStyle(color: P.textFaint, fontSize: 13))
          else
            ...top.map((e) {
              final frac = e.value / top.first.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  CountryFlag(_ccOf(e.key)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key,
                                style: const TextStyle(
                                    color: P.text, fontSize: 13)),
                            Text(_bytes(e.value),
                                style: const TextStyle(
                                    color: P.textFaint, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: frac.clamp(0.02, 1.0),
                            minHeight: 5,
                            backgroundColor: P.surfaceHi,
                            valueColor:
                                const AlwaysStoppedAnimation(P.lime),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }

  // Обратное сопоставление страны → код (для флага).
  static String _ccOf(String country) => switch (country) {
        'Германия' => 'DE',
        'Нидерланды' => 'NL',
        'Финляндия' => 'FI',
        'Россия' => 'RU',
        'США' => 'US',
        'Великобритания' => 'GB',
        _ => '??',
      };
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
