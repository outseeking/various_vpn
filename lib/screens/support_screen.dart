/// Поддержка: встроенный чат прямо в приложении (APP_LOGIC.md §9) + быстрый
/// переход в Telegram-поддержку. Дизайн черновой.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/link_tile.dart';

class SupportScreen extends StatefulWidget {
  /// true — экран показан как вкладка в общей оболочке (без стрелки «назад»).
  final bool inShell;
  const SupportScreen({super.key, this.inShell = false});

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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.inShell,
        title: Text(L.t('sup_title')),
        actions: [
          IconButton(
            tooltip: L.t('open_in_tg'),
            icon: const Icon(Icons.telegram),
            onPressed: () => launchUrl(Uri.parse(Brand.support),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context)
            .unfocus(), // тап по пустому — скрыть клавиатуру
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Expanded(
              // Пустой чат — не голая надпись, а понятное «что тут делать»
              // плюс кликабельные способы связи (правило empty-states).
              child: chat.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                      children: [
                        const Icon(Icons.forum_outlined,
                            size: 40, color: P.limeText),
                        const SizedBox(height: 14),
                        Text(L.t('sup_empty_t'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: P.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(L.t('sup_empty_b'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: P.textFaint, fontSize: 13, height: 1.5)),
                        const SizedBox(height: 22),
                        LinkTile(
                          icon: Icons.telegram,
                          title: L.t('sup_in_tg'),
                          subtitle: '@variousvpnbot',
                          url: Brand.support,
                        ),
                        const SizedBox(height: 8),
                        LinkTile(
                          icon: Icons.campaign_outlined,
                          title: L.t('channel'),
                          subtitle:
                              Brand.channel.replaceFirst('https://t.me/', '@'),
                          url: Brand.channel,
                        ),
                      ],
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
                              // Свои сообщения — фирменным лаймом, ответы
                              // поддержки — нейтральной поверхностью.
                              color: m.fromUser
                                  ? P.lime.withValues(alpha: 0.16)
                                  : P.surfaceUp,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft:
                                    Radius.circular(m.fromUser ? 16 : 5),
                                bottomRight:
                                    Radius.circular(m.fromUser ? 5 : 16),
                              ),
                              border: Border.all(
                                  color: m.fromUser
                                      ? P.lime.withValues(alpha: 0.30)
                                      : P.surfaceHi),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.text,
                                    style: const TextStyle(
                                        color: P.text,
                                        fontSize: 14,
                                        height: 1.4)),
                                const SizedBox(height: 3),
                                Text(m.hhmm,
                                    style: const TextStyle(
                                        color: P.textFaint, fontSize: 10.5)),
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
