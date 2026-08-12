/// Добавление подписки: ID, ссылка, готовые конфиги или QR-код.
///
/// Экран приведён к общему стилю приложения — раньше он был на стандартных
/// материаловских кнопках и выглядел как из другого продукта. Порядок тот же,
/// что везде: сначала главный путь (поле ввода), потом альтернативы.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/tap_scale.dart';
import 'home_screen.dart';
import 'qr_import_screen.dart';
import '../widgets/app_toast.dart';

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
      AppToast.ok(context, '${L.t('imp_ok')}: ${state.servers.length}');
      if (widget.firstRun) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } else {
      AppToast.error(context, state.lastError ?? L.t('imp_fail'));
    }
  }

  Future<void> _pasteAndImport() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (!mounted) return;
      AppToast.error(context, L.t('imp_clip_empty'));
      return;
    }
    _ctrl.text = txt;
    await _import();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('imp_title'))),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(L.t('imp_hint2'),
                style: const TextStyle(
                    color: P.textDim, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 18),
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
              style: const TextStyle(color: P.text, fontSize: 14),
              decoration: InputDecoration(hintText: L.t('imp_field_hint')),
            ),
            const SizedBox(height: 16),
            _Primary(
              label: L.t('imp_btn'),
              icon: Icons.download_rounded,
              busy: _busy,
              onTap: _busy ? null : _import,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _Secondary(
                  label: L.t('imp_qr'),
                  icon: Icons.qr_code_scanner,
                  onTap: _busy ? null : _openQr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Secondary(
                  label: L.t('imp_paste'),
                  icon: Icons.content_paste_rounded,
                  onTap: _busy ? null : _pasteAndImport,
                ),
              ),
            ]),
            const SizedBox(height: 26),
            // Где взять подписку — сразу ведём в бота, чтобы новичок не терялся.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: P.surfaceLo,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: P.surfaceHi),
              ),
              child: Column(children: [
                Text(L.t('imp_where'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: P.textDim, fontSize: 13, height: 1.45)),
                const SizedBox(height: 12),
                _Secondary(
                  label: L.t('imp_get_in_bot'),
                  icon: Icons.smart_toy_outlined,
                  onTap: () => launchUrl(Uri.parse(Brand.bot),
                      mode: LaunchMode.externalApplication),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQr() async {
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const QrImportScreen()));
    if (ok != true || !mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

/// Главная кнопка экрана — фирменный градиент, состояние загрузки внутри.
class _Primary extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;
  const _Primary({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      haptic: true,
      scale: 0.975,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: P.grad,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                  color: P.lime.withValues(alpha: 0.26),
                  blurRadius: 20,
                  spreadRadius: -6,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: P.onLime),
              )
            else
              Icon(icon, size: 19, color: P.onLime),
            const SizedBox(width: 9),
            Text(label,
                style: const TextStyle(
                    color: P.onLime,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

/// Второстепенная кнопка — контур, тот же ритм скруглений и высоты.
class _Secondary extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _Secondary(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
          decoration: BoxDecoration(
            color: P.surfaceLo,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: P.surfaceHi),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: P.limeText),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: P.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}
