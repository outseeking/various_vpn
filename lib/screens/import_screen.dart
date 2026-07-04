/// Импорт подписки: вставить ссылку (грузим с сервера) ИЛИ вставить сам текст
/// подписки/ссылку конфига. QR-сканер добавим на мобильной сборке (mobile_scanner
/// не работает в Web). Дизайн черновой.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'home_screen.dart';
import 'qr_import_screen.dart';

class ImportScreen extends StatefulWidget {
  /// true — открыт в потоке первого входа (после успеха идём на главный экран).
  final bool firstRun;
  const ImportScreen({super.key, this.firstRun = false});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _import() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final ok = await state.importSmart(text); // сам определит ссылку или текст
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импортировано серверов: ${state.servers.length}')),
      );
      if (widget.firstRun) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.lastError ?? 'Ошибка импорта')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт подписки')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Вставь ссылку подписки из бота (начинается с https://) — '
              'или сам текст конфигов (vless://…, base64-подписку).',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              minLines: 3,
              maxLines: 6,
              // ссылка/конфиг: без автокапитализации и автокоррекции, иначе
              // «Https://» ломает разбор; URL-клавиатура удобнее.
              keyboardType: TextInputType.url,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'https://nl1.ug-connect.site:8088/sub/…\n'
                    'или vless://…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.download),
              label: const Text('Импортировать'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const QrImportScreen()),
                      );
                      if (ok == true && mounted) {
                        if (widget.firstRun) {
                          Navigator.of(context).pushReplacement(MaterialPageRoute(
                              builder: (_) => const HomeScreen()));
                        } else {
                          Navigator.of(context).pop(true);
                        }
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Добавить по QR-коду'),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
