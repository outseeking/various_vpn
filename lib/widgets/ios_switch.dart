/// Тумблер в стиле iOS — с настоящей физикой, а не просто круглый Switch.
///
/// Material-переключатель на iOS выглядит чужеродно, а CupertinoSwitch не даёт
/// фирменного цвета и не повторяет мелочи, из которых и складывается ощущение
/// «родного» элемента. Поэтому он собран здесь целиком.
///
/// Что именно скопировано у системного тумблера — каждая мелочь замечена не
/// глазом, а по ощущению «что-то не то»:
///
///  * размеры 51×31 при бегунке 27 и отступе 2 — ровно те, что у Apple;
///  * бегунок ВЫТЯГИВАЕТСЯ, пока палец удерживает его: это главный признак
///   «живого» тумблера, без него он кажется картинкой;
///  * его можно ПЕРЕТАСКИВАТЬ, а не только нажимать, и отпускание за середину
///   доводит переключение до конца;
///  * дорожка перекрашивается не линейно, а вместе с бегунком, поэтому цвет
///   «догоняет» движение;
///  * отклик пальцу — лёгкая вибрация в момент смены состояния, а не в момент
///   касания.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';

class IosSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Цвет включённой дорожки. По умолчанию — фирменный лайм.
  final Color activeColor;

  const IosSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = P.lime,
  });

  @override
  State<IosSwitch> createState() => _IosSwitchState();
}

class _IosSwitchState extends State<IosSwitch>
    with SingleTickerProviderStateMixin {
  // Размеры системного тумблера iOS.
  static const _w = 51.0;
  static const _h = 31.0;
  static const _pad = 2.0;
  static const _thumb = _h - _pad * 2; // 27
  static const _travel = _w - _thumb - _pad * 2; // 20

  /// Насколько бегунок вытягивается под пальцем.
  static const _stretch = 4.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.value ? 1 : 0,
  );

  /// Палец сейчас на тумблере: бегунок вытянут.
  bool _pressed = false;

  /// Идёт перетаскивание — анимацией управляет палец, а не кривая.
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant IosSwitch old) {
    super.didUpdateWidget(old);
    // Значение могло измениться снаружи (например, сбросом настроек).
    if (widget.value != old.value && !_dragging) {
      widget.value ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  void _settle(bool to) {
    // Пружина, а не линейное доведение: у системного тумблера бегунок слегка
    // «доезжает» по инерции, и без этого движение кажется механическим.
    _c.animateTo(to ? 1 : 0,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOutBack);
    if (to != widget.value) {
      HapticFeedback.lightImpact();
      widget.onChanged!(to);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: _enabled
            ? () {
                setState(() => _pressed = false);
                _settle(!widget.value);
              }
            : null,
        onHorizontalDragStart: _enabled
            ? (_) => setState(() {
                  _pressed = true;
                  _dragging = true;
                })
            : null,
        onHorizontalDragUpdate: _enabled
            ? (d) => _c.value += d.primaryDelta! / _travel
            : null,
        onHorizontalDragEnd: _enabled
            ? (_) {
                setState(() {
                  _pressed = false;
                  _dragging = false;
                });
                // Отпустили за серединой — доводим до включённого.
                _settle(_c.value >= 0.5);
              }
            : null,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value.clamp(0.0, 1.0);
            final width = _thumb + (_pressed ? _stretch : 0);
            // Вытягивание идёт «от края»: слева бегунок растёт вправо, справа —
            // влево, как будто упирается в стенку дорожки.
            final x = _pad + t * (_travel - (_pressed ? _stretch : 0) * t);

            return Opacity(
              opacity: _enabled ? 1 : 0.5,
              child: SizedBox(
                width: _w,
                height: _h,
                child: Stack(children: [
                  // дорожка
                  Container(
                    width: _w,
                    height: _h,
                    decoration: BoxDecoration(
                      color: Color.lerp(P.surfaceUp, widget.activeColor, t),
                      borderRadius: BorderRadius.circular(_h / 2),
                      border: Border.all(
                        color: Color.lerp(P.surfaceHi,
                            widget.activeColor.withValues(alpha: 0.0), t)!,
                        width: 0.5,
                      ),
                    ),
                  ),
                  // бегунок
                  Positioned(
                    left: x,
                    top: _pad,
                    child: Container(
                      width: width,
                      height: _thumb,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_thumb / 2),
                        boxShadow: const [
                          // Две тени, как у системного: широкая мягкая для
                          // объёма и узкая под самым бегунком для контакта.
                          BoxShadow(
                              color: Color(0x26000000),
                              blurRadius: 8,
                              offset: Offset(0, 3)),
                          BoxShadow(
                              color: Color(0x29000000),
                              blurRadius: 1,
                              offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
