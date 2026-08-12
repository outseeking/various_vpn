/// Отклик на нажатие для всех кастомных кнопок и строк приложения.
///
/// При касании элемент «вжимается» и слегка притухает, при отпускании
/// возвращается на пружине с коротким перелётом — так тап ощущается физическим,
/// а не как переключение картинки. Раньше это был линейный easeOut на 110 мс:
/// технически отклик был, но «дешёвый».
///
/// Отдельно: вжатие идёт МГНОВЕННО (палец не должен ждать), а возврат —
/// пружиной; и то и другое прерываемо, повторный тап не «застревает».
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion.dart';

class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Насколько сжимать. 0.96 — строка списка, 0.97 — крупная карточка.
  final double scale;
  final HitTestBehavior behavior;

  /// Лёгкий тактильный отклик в момент касания. Для главных действий.
  final bool haptic;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.behavior = HitTestBehavior.opaque,
    this.haptic = false,
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: M.tap,
    reverseDuration: const Duration(milliseconds: 340),
  );

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() {
    if (!_enabled) return;
    if (widget.haptic) HapticFeedback.selectionClick();
    _c.forward();
  }

  void _up() {
    if (!_enabled) return;
    _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          // Вниз — ровно, вверх — пружиной с перелётом.
          final t = _c.status == AnimationStatus.reverse
              ? M.spring.transform(1 - _c.value)
              : 1 - _c.value;
          final k = widget.scale + (1 - widget.scale) * t;
          return Transform.scale(
            scale: k,
            // Притухание усиливает ощущение нажатия, но не настолько, чтобы
            // элемент «пропадал»: минимум 0.82 — он всё ещё читается.
            child: Opacity(opacity: 1 - (1 - t) * 0.18, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}
