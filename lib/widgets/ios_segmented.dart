/// Сегментированный переключатель в стиле iOS — с перетаскиванием.
///
/// Выбранный сегмент — не перекрашенная кнопка, а «таблетка», которую можно
/// ВЕСТИ пальцем. Это важнее, чем кажется: тап переключает вслепую, а
/// перетаскивание показывает промежуточные варианты по дороге, и палец
/// останавливается там, где надо, не отрываясь от экрана.
///
/// Мелочи, из которых складывается ощущение системного элемента:
///  * таблетка следует за пальцем без задержки, а отпускание доводит её до
///    ближайшей позиции пружиной;
///  * пока её ведут, она слегка увеличивается — как приподнятая над стеклом;
///  * подпись под таблеткой темнеет ПОСТЕПЕННО, по мере наезда, а не скачком;
///  * отклик вибрацией срабатывает на пересечении границы сегмента, а не в
///    момент отпускания.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import '../theme/motion.dart';

class IosSegmented<T> extends StatefulWidget {
  final List<(T value, String label)> items;
  final T value;
  final ValueChanged<T> onChanged;

  const IosSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  State<IosSegmented<T>> createState() => _IosSegmentedState<T>();
}

class _IosSegmentedState<T> extends State<IosSegmented<T>>
    with SingleTickerProviderStateMixin {
  static const _pad = 3.0;
  static const _height = 36.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: M.state,
    // Позиция таблетки в «номерах сегментов»: 0, 1, 2… Дробные значения — это
    // и есть состояние на полпути, ради которого всё затевалось.
    lowerBound: 0,
    upperBound: (widget.items.length - 1).toDouble(),
    value: 0,
  );

  bool _dragging = false;
  int _lastHaptic = 0;

  @override
  void initState() {
    super.initState();
    _c.value = _indexOf(widget.value).toDouble();
  }

  int _indexOf(T v) {
    final i = widget.items.indexWhere((e) => e.$1 == v);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant IosSegmented<T> old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_dragging) {
      _c.animateTo(_indexOf(widget.value).toDouble(),
          duration: M.state, curve: Curves.easeOutBack);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle(int index) {
    _c.animateTo(index.toDouble(),
        duration: M.state, curve: Curves.easeOutBack);
    final v = widget.items[index].$1;
    if (v != widget.value) widget.onChanged(v);
  }

  /// Вибрация на пересечении границы сегмента — как у системного колеса выбора.
  void _hapticOnCross() {
    final near = _c.value.round();
    if (near != _lastHaptic) {
      _lastHaptic = near;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final count = widget.items.length;
      final cell = (box.maxWidth - _pad * 2) / count;

      void moveTo(double dx) {
        final pos = ((dx - _pad) / cell - 0.5).clamp(0.0, (count - 1) * 1.0);
        _c.value = pos;
        _hapticOnCross();
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => moveTo(d.localPosition.dx),
        onTapUp: (d) {
          final i = ((d.localPosition.dx - _pad) / cell)
              .floor()
              .clamp(0, count - 1);
          _settle(i);
        },
        onHorizontalDragStart: (d) {
          setState(() => _dragging = true);
          moveTo(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => moveTo(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          _settle(_c.value.round().clamp(0, count - 1));
        },
        child: Container(
          padding: const EdgeInsets.all(_pad),
          decoration: BoxDecoration(
            color: P.surfaceLo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: P.surfaceHi, width: 0.5),
          ),
          child: SizedBox(
            height: _height,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Stack(children: [
                  // Таблетка. Именно она несёт смысл переключения, поэтому
                  // рисуется под подписями и следует за пальцем без задержки.
                  Positioned(
                    left: cell * _c.value,
                    top: 0,
                    bottom: 0,
                    width: cell,
                    child: Transform.scale(
                      scale: _dragging ? 1.06 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: P.grad,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: _dragging ? 0.45 : 0.25),
                              blurRadius: _dragging ? 12 : 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Expanded(
                          child: Center(
                            // Подпись темнеет постепенно, по мере наезда
                            // таблетки: скачок цвета выдал бы, что элемент
                            // «перерисовался», а не переехал.
                            child: _Label(
                              text: widget.items[i].$2,
                              t: (1 - (_c.value - i).abs()).clamp(0.0, 1.0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ]);
              },
            ),
          ),
        ),
      );
    });
  }
}

class _Label extends StatelessWidget {
  final String text;

  /// Насколько таблетка наехала на эту подпись: 0 — мимо, 1 — точно под ней.
  final double t;

  const _Label({required this.text, required this.t});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Color.lerp(P.textFaint, P.onLime, t),
        fontSize: 13.5,
        fontWeight: t > 0.5 ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }
}
