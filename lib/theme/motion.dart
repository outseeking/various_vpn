/// ЕДИНЫЕ токены движения. Всё приложение должно двигаться в одном ритме:
/// одинаковые длительности и кривые для нажатий, переходов, раскрытий и шторок.
/// Раньше каждая анимация выбирала свои 110/200/220/250/300 мс и Curves.easeOut
/// «на глаз» — из-за разнобоя интерфейс ощущался собранным из кусков.
///
/// Правила, по которым подобраны значения:
///  • микро-отклик (нажатие) — 90–140 мс, иначе палец «опережает» картинку;
///  • переход состояния — 220 мс, вход мягче выхода;
///  • выход короче входа (~65%) — так интерфейс кажется отзывчивым;
///  • пружина вместо линейности — движение «живое», а не механическое.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class M {
  M._();

  // --- длительности ---
  /// Отклик на палец: нажатие, подсветка, галочка.
  static const tap = Duration(milliseconds: 120);

  /// Смена состояния: раскрытие, переключение, появление плашки.
  static const state = Duration(milliseconds: 220);

  /// Переход между экранами и появление шторок.
  static const page = Duration(milliseconds: 320);

  /// Уход экрана/шторки — заметно короче входа.
  static const pageOut = Duration(milliseconds: 210);

  /// Крупное «дорогое» движение (герой-элементы, раскрытие карточки сессии).
  static const slow = Duration(milliseconds: 420);

  /// Задержка между элементами списка при каскадном появлении.
  static const stagger = Duration(milliseconds: 40);

  // --- кривые ---
  /// Вход: быстрый старт, мягкая посадка. Основная кривая приложения.
  static const enter = Cubic(0.16, 1.0, 0.3, 1.0); // easeOutExpo-подобная

  /// Выход: плавный разгон, быстрый уход.
  static const exit = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Универсальная для смены состояния (туда-обратно симметрично).
  static const standard = Cubic(0.4, 0.0, 0.2, 1.0);

  /// Пружина с лёгким перелётом — для нажатий и появления акцентов.
  static const spring = _Spring();
}

/// Затухающая пружина: 1 - e^(-6.2t)·cos(2.2πt). Даёт один короткий перелёт
/// и мягкое возвращение — движение читается как физическое, а не как «анимация».
class _Spring extends Curve {
  const _Spring();

  @override
  double transformInternal(double t) =>
      1 - math.exp(-6.2 * t) * math.cos(2.2 * math.pi * t);
}

/// Переход между экранами: содержимое въезжает снизу с лёгким масштабом и
/// растворением, назад — уходит быстрее. Направление задаёт иерархию: «глубже»
/// = снизу вверх (см. правило hierarchy-motion).
class AppPageTransitions extends PageTransitionsBuilder {
  const AppPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inCurve = CurvedAnimation(
      parent: animation,
      curve: M.enter,
      reverseCurve: M.exit.flipped,
    );
    // Уходящий вниз экран слегка отъезжает и притухает — появляется ощущение
    // глубины, а не подмены картинки.
    final outCurve =
        CurvedAnimation(parent: secondaryAnimation, curve: M.standard);

    return FadeTransition(
      opacity: inCurve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.035), end: Offset.zero)
            .animate(inCurve),
        child: ScaleTransition(
          scale: Tween(begin: 1.0, end: 0.97).animate(outCurve),
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.72).animate(outCurve),
            child: child,
          ),
        ),
      ),
    );
  }
}
