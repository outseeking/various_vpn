/// Отрисовывает ВСЕ флаги в одну картинку — чтобы проверить их глазами, а не
/// верить, что «наверное нарисовалось». Заодно ловит падения рисовалок.
///
/// Запуск: flutter test test/flags_test.dart
/// Результат: build/flags_preview.png
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/widgets/flag.dart';

void main() {
  testWidgets('все флаги рисуются', (tester) async {
    // EU страной не считается (у узла «Европа» полезнее своя ремарка, чем
    // подпись «Европа»), но флаг у него есть — в превью он тоже нужен.
    final codes = {...countryCodes, 'EU'}.toList()..sort();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: const ValueKey('sheet'),
        child: Container(
          color: const Color(0xFF0C1324),
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final cc in codes)
                SizedBox(
                  width: 64,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CountryFlag(cc, width: 44),
                    const SizedBox(height: 3),
                    Text(cc,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 10)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Сама отрисовка уже проверена: pumpAndSettle упал бы на любом исключении
    // в рисовалке. Дальше — только превью для просмотра глазами.
    //
    // Растеризация обязана идти внутри runAsync: toImage ждёт настоящий кадр
    // от движка, а фейковые часы тестового окружения его не дают — без этого
    // тест печатал результат и после навсегда зависал. Картинку освобождаем
    // руками, иначе живой ui.Image держит тест открытым.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('sheet')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.5);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build').createSync(recursive: true);
        File('build/flags_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    expect(codes.length, greaterThan(80));
    // ignore: avoid_print
    print('нарисовано флагов: ${codes.length} → build/flags_preview.png');
  });
}
