/// ЕДИНЫЙ блок «подключить подписку». Одна схема на всё приложение:
///
///   ГЛАВНОЕ  — вход по ID из бота: поле прямо здесь, вставил число → готово.
///   АЛЬТЕРНАТИВЫ — ссылка и QR-код: видимы сразу, но легче по весу.
///
/// Раньше каждый экран (вход, инструкция, шторка активации, главная) предлагал
/// свой набор кнопок в своём порядке — человек каждый раз заново выбирал из
/// четырёх равнозначных вариантов и терялся. Теперь путь один и он везде
/// выглядит одинаково: узнал один раз — узнаёшь везде.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../platform.dart';
import '../screens/import_screen.dart';
import '../screens/qr_import_screen.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import 'tap_scale.dart';
import 'app_toast.dart';

class ConnectWays extends StatefulWidget {
  /// Вызывается после успешного входа (обычно — уйти на главный экран).
  final VoidCallback? onSuccess;

  /// Компактный вид (для шторок и вторичных экранов): без пояснения снизу.
  final bool compact;

  const ConnectWays({super.key, this.onSuccess, this.compact = false});

  @override
  State<ConnectWays> createState() => _ConnectWaysState();
}

class _ConnectWaysState extends State<ConnectWays> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  bool _busy = false;
  // ID, найденный в буфере обмена: предлагаем его одной кнопкой вместо того,
  // чтобы человек вручную вставлял число, вернувшись из бота.
  String? _clip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sniffClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Ключевой момент воронки: человек вернулся из Telegram, где ему выдали ID.
    // Проверяем буфер именно в этот момент и предлагаем войти одним тапом.
    if (s == AppLifecycleState.resumed) _sniffClipboard();
  }

  Future<void> _sniffClipboard() async {
    // Без просьбы в буфер не заглядываем там, где система это показывает
    // человеку: он ничего не нажимал, а поверх экрана всплывает «приложение
    // вставило из…». Кнопка вставки ниже никуда не делась.
    if (!Caps.clipboardSniff) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final m = RegExp(r'\b\d{6,15}\b').firstMatch(data?.text ?? '');
    final id = m?.group(0);
    if (!mounted || id == null || id == _ctrl.text.trim()) return;
    setState(() => _clip = id);
  }

  Future<void> _submit([String? forced]) async {
    final id = (forced ?? _ctrl.text).trim();
    if (id.isEmpty) {
      _snack(L.t('gs_id_empty'));
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final ok = await state.importFromTgId(id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _clip = null;
    });
    if (ok) {
      widget.onSuccess?.call();
      return;
    }
    // Нет подписки — это не ошибка ввода, а развилка: человеку нужна подписка,
    // и путь к ней должен быть здесь же. Остальные беды (сервер не ответил,
    // пустое поле) остаются короткой плашкой.
    if (state.needsSubscription) {
      await showNoSubscriptionSheet(context);
      return;
    }
    _snack(state.lastError ?? L.t('gs_id_empty'));
  }

  void _snack(String text) => AppToast.show(context, text);

  void _push(Widget screen) => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen))
          .then((_) {
        // Импорт по ссылке/QR мог выдать доступ — сообщаем наверх.
        if (mounted && context.read<AppState>().hasAccess) {
          widget.onSuccess?.call();
        }
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- ГЛАВНЫЙ путь: ID ---
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: P.surfaceLo,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: P.lime.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.bolt, color: P.limeText, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(L.t('gs_id_title'),
                      style: const TextStyle(
                          color: P.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 10),

              // Подсказка «войти как <ID из буфера>» — самый короткий путь.
              if (_clip != null) ...[
                TapScale(
                  onTap: _busy ? null : () => _submit(_clip),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: P.lime.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: P.lime.withValues(alpha: 0.45)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.content_paste_go_rounded,
                          size: 18, color: P.limeText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(L.t('cw_clip', {'id': _clip!}),
                            style: const TextStyle(
                                color: P.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 17, color: P.limeText),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: P.text, fontSize: 16),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: L.t('gs_id_hint'),
                      hintStyle:
                          const TextStyle(color: P.textFaint, fontSize: 13),
                      filled: true,
                      fillColor: P.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: P.surfaceHi),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: P.surfaceHi),
                      ),
                      suffixIcon: IconButton(
                        tooltip: L.t('gs_id_paste'),
                        icon: const Icon(Icons.content_paste_rounded,
                            size: 18, color: P.limeText),
                        onPressed: () async {
                          final d =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final m =
                              RegExp(r'\d{5,15}').firstMatch(d?.text ?? '');
                          if (m != null) _ctrl.text = m.group(0)!;
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TapScale(
                  onTap: _busy ? null : () => _submit(),
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: P.grad,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: P.onLime))
                        : Text(L.t('gs_id_go'),
                            style: const TextStyle(
                                color: P.onLime,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              if (!widget.compact) ...[
                const SizedBox(height: 8),
                Text(L.t('gs_id_help'),
                    style: const TextStyle(
                        color: P.textFaint, fontSize: 11.5, height: 1.35)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // --- АЛЬТЕРНАТИВЫ ---
        Row(children: [
          Expanded(
            child: _WayButton(
              icon: Icons.link,
              label: L.t('gs_way_link'),
              onTap: () => _push(const ImportScreen(firstRun: true)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _WayButton(
              icon: Icons.qr_code_scanner,
              label: L.t('gs_way_qr'),
              onTap: () => _push(const QrImportScreen()),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Компактная кнопка альтернативного способа (ссылка / QR). Видима сразу —
/// человеку с QR не нужно ничего разворачивать, — но заметно легче главной.
class _WayButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _WayButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: P.surfaceLo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: P.surfaceHi),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: P.limeText),
          const SizedBox(width: 7),
          // Flexible обязателен: на узком экране «По QR-коду» не помещается в
          // половину строки и вылезает за край карточки.
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: P.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}


/// Шторка «нужна подписка» — ответ на попытку войти по ID без оплаты.
Future<void> showNoSubscriptionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 14,
          right: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: P.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: P.violetSoft.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: P.violetSoft.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium,
                  size: 24, color: P.violetSoft),
            ),
            const SizedBox(height: 14),
            Text(L.t('nosub_title'),
                style: const TextStyle(
                    color: P.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(L.t('nosub_body'),
                style: const TextStyle(
                    color: P.textDim, fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 18),
            TapScale(
              haptic: true,
              onTap: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse('${Brand.bot}?start=buy'),
                    mode: LaunchMode.externalApplication);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: P.grad,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(L.t('nosub_cta'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: P.onLime,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L.t('later'),
                    style: const TextStyle(color: P.textFaint, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
