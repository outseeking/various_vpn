/// «Жидкое стекло» — поверхности в духе свежих iOS.
///
/// Стекло — это не «полупрозрачный прямоугольник». Убедительным его делают три
/// вещи разом, и без любой из них поверхность выглядит просто мутной плашкой:
///
///  1. РАЗМЫТИЕ ФОНА. Слой должен показывать, что под ним что-то есть. Отсюда
///     BackdropFilter, а не полупрозрачная заливка.
///  2. БЛИК ПО ВЕРХНЕЙ КРОМКЕ. У настоящего стекла свет ловит фаска: вверху
///     кромка светлее, внизу почти исчезает. Одна ровная рамка по кругу
///     мгновенно выдаёт подделку.
///  3. ВНУТРЕННЕЕ СВЕЧЕНИЕ СВЕРХУ. Мягкое пятно под верхним краем — толщина
///     стекла. Без него слой плоский.
///
/// Стоимость: BackdropFilter заставляет систему перерисовывать всё под собой.
/// На слабых устройствах это заметно, поэтому размытие там отключается — см.
/// [GlassPanel.blurred].
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// Размывать ли фон. Выключается в режиме для слабых устройств: размытие —
  /// самая дорогая часть картинки, а рисунок без него остаётся приличным.
  final bool blurred;

  /// Насколько поверхность «толстая»: от лёгкой плёнки до плотного стекла.
  final double opacity;

  /// Оттенок стекла. По умолчанию нейтральный — цвет даёт то, что под ним.
  final Color? tint;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.blurred = true,
    this.opacity = 0.6,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final base = (tint ?? P.surface).withValues(alpha: opacity);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // Заливка сверху вниз: у стекла верх ловит больше света.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, 0.06)!,
            base,
          ],
        ),
      ),
      child: child,
    );

    if (blurred) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(children: [
        content,
        // Кромка: ярче сверху, гаснет к низу. Рисуем поверх и не задеваем
        // размеры — рамка в декорации сдвинула бы содержимое.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: GradientBoxBorder(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.28),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Внутреннее свечение под верхней кромкой — «толщина» стекла.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: radius * 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Рамка с градиентом. В Flutter такой из коробки нет: обычный Border красится
/// одним цветом, а стеклу нужна кромка, гаснущая книзу.
class GradientBoxBorder extends BoxBorder {
  final Gradient gradient;
  final double width;

  const GradientBoxBorder({required this.gradient, this.width = 1});

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  BorderSide get top => BorderSide.none;

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  void paint(Canvas canvas, Rect rect,
      {BoxShape shape = BoxShape.rectangle,
      BorderRadius? borderRadius,
      ImageConfiguration configuration = ImageConfiguration.empty,
      TextDirection? textDirection}) {
    final paint = Paint()
      ..strokeWidth = width
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke;
    final r = borderRadius ?? BorderRadius.zero;
    canvas.drawRRect(r.toRRect(rect).deflate(width / 2), paint);
  }

  @override
  ShapeBorder scale(double t) =>
      GradientBoxBorder(gradient: gradient, width: width * t);
}
