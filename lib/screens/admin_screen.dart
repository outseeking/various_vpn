/// Админ-панель (видна владельцу). По APP_LOGIC.md §7: метрики, ошибки
/// приложения и фундамент под ИИ-агента админа в Telegram.
/// Большинство метрик придёт с бэкенда (TODO эндпоинт админ-статистики); пока
/// показываем то, что доступно локально, и ошибки из логов. Дизайн черновой.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/log_entry.dart';
import '../state/app_state.dart';

const _botUrl = 'https://t.me/variousvpnbot';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final errors = state.logs.where((e) => e.kind == LogKind.error).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Админ-панель')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- метрики ---
          Text('Метрики', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatCard(label: 'Серверов', value: '${state.servers.length}'),
              const SizedBox(width: 12),
              _StatCard(
                label: 'Подписка',
                value: state.hasServers ? 'есть' : '—',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.insights),
              title: Text('Пользователи / доход / убыток'),
              subtitle: Text('Подтянем с бэкенда (эндпоинт админ-статистики — TODO)'),
            ),
          ),

          const SizedBox(height: 16),
          // --- ошибки приложения ---
          Text('Ошибки приложения (${errors.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (errors.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Ошибок нет'),
              ),
            )
          else
            ...errors.take(20).map((e) => Card(
                  child: ListTile(
                    dense: true,
                    leading: Text(e.kind.icon),
                    title: Text(e.text),
                    trailing: Text(e.hhmmss,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                )),

          const SizedBox(height: 16),
          // --- ИИ-агент (будущее) ---
          Text('ИИ-агент админа', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.smart_toy),
              title: Text('ИИ-агент в Telegram'),
              subtitle: Text(
                'Видит баги приложения и бэкенда, часть чинит сам, шлёт дайджест '
                'прибыли/убытка. Отдельная большая фича (APP_LOGIC §7).',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(_botUrl),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Открыть бота-админку'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
