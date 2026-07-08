/// Поддержка: встроенный чат прямо в приложении (APP_LOGIC.md §9) + быстрый
/// переход в Telegram-поддержку. Дизайн черновой.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../state/app_state.dart';

const _supportUrl = 'https://t.me/variousvpnsupport';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _ctrl = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // подтягиваем переписку из панели + периодически обновляем (ответы админа)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadSupport();
    });
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<AppState>().loadSupport();
    });
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    context.read<AppState>().sendSupport(text);
    _ctrl.clear();
  }

  Future<void> _attach() async {
    final res = await FilePicker.platform.pickFiles(withData: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.path == null) return;
    if (!mounted) return;
    await context.read<AppState>().sendSupportFile(f.path!, f.name);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<AppState>().supportChat;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(L.t('sup_title')),
        actions: [
          IconButton(
            tooltip: 'Открыть в Telegram',
            icon: const Icon(Icons.telegram),
            onPressed: () => launchUrl(Uri.parse(_supportUrl),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // тап по пустому — скрыть клавиатуру
        behavior: HitTestBehavior.opaque,
        child: Column(
        children: [
          Expanded(
            child: chat.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Напиши нам прямо здесь — ответим в приложении.\n'
                        'Или нажми значок Telegram вверху, чтобы написать в чат.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: chat.length,
                    itemBuilder: (_, i) {
                      final m = chat[i];
                      return Align(
                        alignment: m.fromUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 280),
                          decoration: BoxDecoration(
                            color: m.fromUser
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.text),
                              const SizedBox(height: 2),
                              Text(m.hhmm,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: L.t('sup_attach'),
                    onPressed: _attach,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: L.t('sup_hint'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }
}
