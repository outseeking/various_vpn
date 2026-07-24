/// Импорт подписки: вставить ссылку (грузим с сервера) ИЛИ вставить сам текст
/// подписки/ссылку конфига. QR-сканер добавим на мобильной сборке (mobile_scanner
/// не работает в Web). Дизайн черновой.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
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
        SnackBar(content: Text('${L.t('imp_ok')}: ${state.servers.length}')),
      );
      if (widget.firstRun) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
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

  Future<void> _pasteAndImport() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('imp_clip_empty'))),
      );
      return;
    }
    _ctrl.text = txt;
    await _import();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('imp_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(L.t('imp_hint2')),
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
                hintText: 'ID из бота (напр. 1658245753)\n'
                    'или https://…  ·  vless://…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.download),
              label: Text(L.t('imp_btn')),
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
                              builder: (_) => const MainShell()));
                        } else {
                          Navigator.of(context).pop(true);
                        }
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(L.t('imp_qr')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pasteAndImport,
              icon: const Icon(Icons.content_paste),
              label: Text(L.t('imp_paste')),
            ),
            const SizedBox(height: 22),
            // Где взять подписку — сразу ведём в бота, чтобы новичок не терялся.
            Text(L.t('imp_where'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => launchUrl(Uri.parse(Brand.bot),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.smart_toy_outlined),
              label: Text(L.t('imp_get_in_bot')),
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
