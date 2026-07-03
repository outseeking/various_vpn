/// Привязка аккаунта. Два пути:
///  1) По Telegram-ID + код подтверждения (основной, по решению владельца) —
///     требует эндпоинтов на бэкенде (пока заглушка, см. BackendApi).
///  2) Быстрый путь «у меня есть ссылка подписки» → экран импорта (работает уже
///     сейчас, т.к. агрегатор подписки в проде).
/// Дизайн черновой.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend_api.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import 'connect_guide_screen.dart';
import 'home_screen.dart';
import 'import_screen.dart';

// Имя бота в Telegram (для кнопки «Открыть бота»).
const _botUrl = 'https://t.me/variousvpnbot';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _idCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _api = BackendApi();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _requestCode() async {
    final id = _idCtrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    // Сохраняем ID локально (от него зависит показ админ-панели владельцу).
    if (id.isNotEmpty) context.read<AppState>().setTgId(id);
    final ok = await _api.requestCode(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codeSent = ok;
      if (!ok) {
        _error = 'Пока не удалось отправить код (привязка по коду ещё '
            'настраивается на сервере). Используй вход по ссылке ниже.';
      }
    });
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _api.verifyCode(_idCtrl.text.trim(), _codeCtrl.text.trim());
    if (!mounted) return;
    if (res.ok && res.subUrl != null) {
      Storage.instance.tgId = _idCtrl.text.trim();
      Storage.instance.authToken = res.token;
      final state = context.read<AppState>();
      final imported = await state.importFromUrl(res.subUrl!);
      if (!mounted) return;
      if (imported) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        return;
      }
    }
    setState(() {
      _busy = false;
      _error = res.error ?? 'Не удалось войти';
    });
  }

  Future<void> _freeTelegram() async {
    final state = context.read<AppState>();
    await state.connectTelegramOnly();
    if (!mounted) return;
    // После включения бесплатного режима показываем инструкцию подключения.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => const ConnectGuideScreen(afterFreeEnable: true)),
    );
  }

  Future<void> _openBot() async {
    final uri = Uri.parse(_botUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Открой бота вручную: @variousvpnbot')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в Various VPN')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- бесплатный VPN только для Telegram (до входа/оплаты) ---
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('🆓 Бесплатный VPN для Telegram',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text(
                      'Работает сразу, без входа и оплаты — но только для Telegram. '
                      'Остальные приложения идут напрямую. Для полного VPN — войди ниже.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _freeTelegram,
                      icon: const Icon(Icons.telegram),
                      label: const Text('Включить бесплатно'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- вход через Telegram ---
            OutlinedButton.icon(
              onPressed: _openBot,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Открыть бота и взять ID'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Открой Telegram-бота Various VPN, возьми свой ID и подключись здесь. '
              'На указанный аккаунт придёт код подтверждения.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _idCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Telegram ID (из бота)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_codeSent) ...[
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Код из Telegram',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _requestCode),
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Войти' : 'Получить код'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Или подключись по ссылке подписки из бота:'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen(firstRun: true)),
              ),
              icon: const Icon(Icons.link),
              label: const Text('Вставить ссылку подписки'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }
}
