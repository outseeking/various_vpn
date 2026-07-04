/// Добавление своих серверов через JSON (до 5). Доступно только когда активно
/// подключение к Various VPN — небольшая привилегия для наших пользователей.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_palette.dart';

class CustomServersScreen extends StatefulWidget {
  const CustomServersScreen({super.key});

  @override
  State<CustomServersScreen> createState() => _CustomServersScreenState();
}

class _CustomServersScreenState extends State<CustomServersScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  static const _example =
      '[\n  "vless://uuid@host:443?security=reality&...#Мой сервер 1",\n'
      '  "vless://uuid@host2:443?security=reality&...#Мой сервер 2"\n]';

  Future<void> _add() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final ok = await state.importCustomServers(_ctrl.text);
    setState(() => _busy = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: P.surface,
      content: Text(ok ? '✅ Свои серверы добавлены' : (state.lastError ?? 'Ошибка')),
    ));
    if (ok) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<AppState>().isConnected;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: const Text('Свои серверы')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            // мягкое объяснение, без акцента
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
                  Row(children: const [
                    Icon(Icons.tune, color: P.limeText, size: 20),
                    SizedBox(width: 8),
                    Text('Для продвинутых',
                        style: TextStyle(
                            color: P.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Можно добавить до 5 собственных серверов через JSON — они '
                    'появятся рядом с нашими. Это личная настройка и доступна '
                    'только когда ты подключён к Various VPN.',
                    style: TextStyle(color: P.textDim, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (!connected)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: P.surfaceLo,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: P.surfaceHi),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outline, color: P.textFaint, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Сначала подключись к Various VPN — потом добавление откроется.',
                      style: TextStyle(color: P.textFaint, fontSize: 13),
                    ),
                  ),
                ]),
              )
            else ...[
              TextField(
                controller: _ctrl,
                minLines: 6,
                maxLines: 12,
                style: const TextStyle(
                    color: P.text, fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: _example,
                  hintStyle: const TextStyle(color: P.textFaint, fontSize: 12),
                  filled: true,
                  fillColor: P.surfaceLo,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: P.surfaceHi)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    if (d?.text != null) _ctrl.text = d!.text!;
                  },
                  icon: const Icon(Icons.paste, size: 18, color: P.limeText),
                  label: const Text('Вставить из буфера',
                      style: TextStyle(color: P.limeText)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _add,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Добавить серверы'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
