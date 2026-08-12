/// Добавление своих серверов через JSON (до 5). Доступно только при активной
/// подписке Various VPN — небольшая привилегия для наших пользователей.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/app_toast.dart';

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
    final state = context.read<AppState>();
    // ЗАЩИТА: без единой рабочей подписки свои серверы не добавляются — иначе
    // через свой конфиг приложением пользовались бы в обход оплаты. Своя
    // подписка другого сервиса этому условию удовлетворяет: человек и так
    // подключается своими серверами, запрещать ему добавить ещё один незачем.
    if (!state.featuresUnlocked) {
      AppToast.show(context, L.t('cs_locked'));
      return;
    }
    setState(() => _busy = true);
    final ok = await state.importCustomServers(_ctrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Успех — просто возвращаемся, серверы уже видны на главном. Без синей плашки.
      Navigator.of(context).pop();
      return;
    }
    AppToast.error(context, state.lastError ?? L.t('error'));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('cs_title'))),
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
                  Row(children: [
                    const Icon(Icons.tune, color: P.limeText, size: 20),
                    const SizedBox(width: 8),
                    Text(L.t('cs_advanced'),
                        style: const TextStyle(
                            color: P.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    L.t('cs_body'),
                    style: const TextStyle(
                        color: P.textDim, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...[
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
                  label: Text(L.t('cs_paste'),
                      style: const TextStyle(color: P.limeText)),
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
                      : Text(L.t('cs_add')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
