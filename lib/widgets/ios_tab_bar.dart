/// Нижняя панель вкладок в стиле iOS — с перетаскиванием подсветки.
///
/// Подсветка активной вкладки не перепрыгивает, а ЕДЕТ, и её можно вести
/// пальцем, не отрывая от экрана: провёл вдоль панели — просмотрел разделы,
/// остановился на нужном. Тап при этом никуда не делся и работает как раньше.
///
/// Ради чего мелочи:
///  * значок и подпись разгораются ПОСТЕПЕННО по мере наезда подсветки —
///    видно, между какими разделами сейчас палец;
///  * активный значок чуть крупнее: размер подсказывает выбор раньше цвета;
///  * вибрация на пересечении границы, а не при отпускании, — палец понимает,
///    что перешёл, ещё до того как посмотрел;
///  * панель уважает нижнюю безопасную зону, иначе на телефонах с жестовой
///    полосой подписи налезают на неё.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import '../theme/motion.dart';
import 'glass.dart';

class IosTabItem {
  final IconData icon;
  final String label;
  const IosTabItem(this.icon, this.label);
}

class IosTabBar extends StatefulWidget {
  final List<IosTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  const IosTabBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  @override
  State<IosTabBar> createState() => _IosTabBarState();
}

class _IosTabBarState extends State<IosTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: M.state,
    lowerBound: 0,
    upperBound: (widget.items.length - 1).toDouble(),
    value: widget.index.toDouble(),
  );

  bool _dragging = false;
  int _lastHaptic = 0;

  @override
  void didUpdateWidget(covariant IosTabBar old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index && !_dragging) {
      _c.animateTo(widget.index.toDouble(),
          duration: M.state, curve: Curves.easeOutBack);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle(int i) {
    _c.animateTo(i.toDouble(), duration: M.state, curve: Curves.easeOutBack);
    if (i != widget.index) widget.onChanged(i);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    // Панель не должна залезать под жестовую полосу — иначе подпись перечёркнута.
    final safe = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 8 + safe),
      child: GlassPanel(
        radius: 26,
        opacity: 0.55,
        padding: const EdgeInsets.all(6),
        child: LayoutBuilder(builder: (context, box) {
          final cell = box.maxWidth / count;

          void moveTo(double dx) {
            _c.value = ((dx / cell) - 0.5).clamp(0.0, (count - 1) * 1.0);
            final near = _c.value.round();
            if (near != _lastHaptic) {
              _lastHaptic = near;
              HapticFeedback.selectionClick();
            }
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                _settle((d.localPosition.dx / cell).floor().clamp(0, count - 1)),
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              moveTo(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) => moveTo(d.localPosition.dx),
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              _settle(_c.value.round().clamp(0, count - 1));
            },
            child: SizedBox(
              height: 54,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  return Stack(children: [
                    Positioned(
                      left: cell * _c.value,
                      top: 0,
                      bottom: 0,
                      width: cell,
                      child: Transform.scale(
                        scale: _dragging ? 1.05 : 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: P.grad,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: P.lime.withValues(
                                    alpha: _dragging ? 0.35 : 0.18),
                                blurRadius: _dragging ? 18 : 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(children: [
                      for (var i = 0; i < count; i++)
                        Expanded(
                          child: _Tab(
                            item: widget.items[i],
                            t: (1 - (_c.value - i).abs()).clamp(0.0, 1.0),
                          ),
                        ),
                    ]),
                  ]);
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IosTabItem item;

  /// Насколько подсветка наехала на эту вкладку: 0 — мимо, 1 — точно под ней.
  final double t;

  const _Tab({required this.item, required this.t});

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(P.textFaint, P.onLime, t)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Размер подсказывает выбор раньше, чем цвет: движение глаз ловит
        // изменение размера быстрее, чем оттенка.
        Icon(item.icon, size: 21 + 2 * t, color: color),
        const SizedBox(height: 3),
        Text(
          item.label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: t > 0.5 ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
