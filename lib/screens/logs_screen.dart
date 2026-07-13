/// Экран логов: лента событий (подключение, переключение серверов, маршруты,
/// ошибки) — что, откуда и куда идёт. По просьбе владельца. Дизайн черновой.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(L.t('logs_title2')),
        actions: [
          IconButton(
            tooltip: L.t('clear'),
            icon: const Icon(Icons.delete_sweep),
            onPressed: state.logs.isEmpty ? null : state.clearLogs,
          ),
        ],
      ),
      body: state.logs.isEmpty
          ? Center(child: Text(L.t('logs_empty')))
          : ListView.separated(
              itemCount: state.logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = state.logs[i];
                return ListTile(
                  dense: true,
                  leading: Text(e.kind.icon, style: const TextStyle(fontSize: 18)),
                  title: Text(e.text),
                  trailing: Text(
                    e.hhmmss,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
    );
  }
}
