/// Уведомления сверху экрана.
///
/// Заменяют стандартный SnackBar. Тот вылезает снизу — ровно там, где палец и
/// панель навигации: сообщение перекрывалось кнопками, а на экране настроек
/// закрывало ту самую строку, которую человек только что нажал. Сверху ничего
/// не заслоняется, и взгляд после нажатия и так идёт вверх, к заголовку.
///
/// Показывается через Overlay, а не через Scaffold: уведомление живёт поверх
/// любого экрана и переживает переход между ними.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import '../theme/motion.dart';

enum ToastKind { ok, error, info }

class AppToast {
  AppToast._();

  static OverlayEntry? _current;
  static int _seq = 0;

  /// Показать уведомление. Повторный вызов заменяет предыдущее — две плашки
  /// друг на друге читались бы хуже, чем одна свежая.
  static void show(
    BuildContext context,
    String text, {
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?.remove();
    _current = null;
    final me = ++_seq;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Toast(
        text: text,
        kind: kind,
        duration: duration,
        onGone: () {
          // Снимаем только своё: пока плашка уезжала, могла успеть появиться
          // следующая, и снятие «текущей» убрало бы уже чужую.
          if (_seq != me) return;
          if (_current == entry) {
            entry.remove();
            _current = null;
          }
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);

    switch (kind) {
      case ToastKind.ok:
        HapticFeedback.lightImpact();
      case ToastKind.error:
        HapticFeedback.heavyImpact();
      case ToastKind.info:
        HapticFeedback.selectionClick();
    }
  }

  static void ok(BuildContext c, String text) =>
      show(c, text, kind: ToastKind.ok);

  static void error(BuildContext c, String text) =>
      show(c, text, kind: ToastKind.error, duration: const Duration(seconds: 4));
}

class _Toast extends StatefulWidget {
  final String text;
  final ToastKind kind;
  final Duration duration;
  final VoidCallback onGone;

  const _Toast({
    required this.text,
    required this.kind,
    required this.duration,
    required this.onGone,
  });

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: M.state,
    reverseDuration: M.pageOut,
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await _c.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  (Color, IconData) get _look => switch (widget.kind) {
        ToastKind.ok => (P.lime, Icons.check_circle_rounded),
        ToastKind.error => (P.danger, Icons.error_rounded),
        ToastKind.info => (P.violetSoft, Icons.info_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (tint, icon) = _look;
    final top = MediaQuery.of(context).padding.top;

    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Пружина только на входе: уход должен быть ровным и коротким, иначе
          // плашка «допрыгивает» уже после того, как внимание ушло обратно.
          final t = _leaving
              ? Curves.easeIn.transform(_c.value)
              : M.spring.transform(_c.value);
          return Opacity(
            opacity: _c.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -46 * (1 - t)),
              child: child,
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            // Смахивание вверх и нажатие убирают плашку сразу: ждать три
            // секунды, когда сообщение уже прочитано, незачем.
            onTap: _dismiss,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: P.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tint.withValues(alpha: 0.45)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(children: [
                Icon(icon, size: 19, color: tint),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.text,
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
