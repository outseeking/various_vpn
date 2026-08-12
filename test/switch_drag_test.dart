/// Переключение вкладок и режима — движением, а не рывком.
///
/// Раньше и то и другое срабатывало только в момент отрыва пальца: пока ведёшь
/// — ничего не происходит, потом всё перекрашивается скачком. Проверить это
/// было нечем: тесты дёргали onChanged напрямую, минуя жест, и «рывок»
/// выглядел в них ровно так же, как плавное движение.
///
/// Поэтому здесь палец ведут вручную — начали, подвинули, ПОСМОТРЕЛИ, не
/// отпуская, и только потом отпустили. Промежуточный кадр и есть предмет
/// проверки.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:various_vpn/widgets/ios_segmented.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 300, child: child)),
      ),
    );

void main() {
  testWidgets('Сегмент: таблетка едет за пальцем, ещё до отпускания',
      (tester) async {
    var value = 'a';
    await tester.pumpWidget(_host(
      StatefulBuilder(
        builder: (context, setState) => IosSegmented<String>(
          value: value,
          onChanged: (v) => setState(() => value = v),
          items: const [('a', 'Авто'), ('b', 'Вручную')],
        ),
      ),
    ));

    // Положение таблетки читаем по её позиции на экране: это единственное, что
    // видит человек. Внутренние поля состояния показали бы лишь намерение.
    // Таблетка — единственный Transform внутри переключателя (её слегка
    // увеличивают, пока ведут). Искать по DecoratedBox нельзя: рамка вокруг
    // всего элемента тоже DecoratedBox и попадается первой.
    Offset pillLeft() => tester.getTopLeft(find.descendant(
        of: find.byType(IosSegmented<String>),
        matching: find.byType(Transform)));

    final start = pillLeft();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(IosSegmented<String>)));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    // Ключевой кадр: палец ещё на экране, а таблетка уже сдвинулась.
    expect(pillLeft().dx, greaterThan(start.dx),
        reason: 'таблетка обязана ехать во время движения, а не после');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(value, 'b');
  });

  testWidgets('Сегмент: тап по дальнему краю тоже переключает', (tester) async {
    var value = 'a';
    await tester.pumpWidget(_host(
      StatefulBuilder(
        builder: (context, setState) => IosSegmented<String>(
          value: value,
          onChanged: (v) => setState(() => value = v),
          items: const [('a', 'Авто'), ('b', 'Вручную')],
        ),
      ),
    ));

    final box = tester.getRect(find.byType(IosSegmented<String>));
    await tester.tapAt(Offset(box.right - 20, box.center.dy));
    await tester.pumpAndSettle();
    expect(value, 'b');
  });
}
