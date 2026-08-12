/// Рендерит глобус в нескольких поворотах — чтобы проверить его глазами.
///
/// Ловит то, чего не поймает никакая проверка на значения: клинья заливки на
/// линии горизонта, пропавшие страны, кривые маркеры.
///
/// Запуск: flutter test test/globe_render_test.dart
/// Результат: build/globe_preview.png
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/geo.dart';
import 'package:various_vpn/widgets/globe.dart';

void main() {
  testWidgets('глобус рисуется без разрывов материков', (tester) async {
    // Страны с разных сторон шара: часть окажется у самого горизонта — именно
    // там раньше вылезали треугольные клинья заливки.
    const views = ['CH', 'RU', 'JP', 'US', 'BR', 'AU'];

    // Карта мира читается из ассетов — это НАСТОЯЩАЯ асинхронная операция.
    // В обычном теле теста время фальшивое, такой Future не завершается
    // никогда, и глобус рисовался бы вообще без материков.
    await tester.runAsync(WorldData.load);

    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: const ValueKey('sheet'),
        child: Container(
          color: const Color(0xFF05070C),
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cc in views)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  GlobeView(
                    size: 220,
                    animationsEnabled: false,
                    focus: Geo.of(cc),
                    connected: false,
                    markers: [
                      for (final m in const [
                        'CH',
                        'JP',
                        'KZ',
                        'EE',
                        'SG',
                        'US',
                        'DE',
                        'BR'
                      ])
                        if (Geo.of(m) != null)
                          GlobeMarker(
                            lon: Geo.of(m)![0],
                            lat: Geo.of(m)![1],
                            label: m,
                            code: m,
                            selected: m == cc,
                          ),
                    ],
                  ),
                  Text(cc,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ]),
            ],
          ),
        ),
      ),
    ));
    // Глобус тянет карту мира из ассетов асинхронно, потом крутится тикером.
    // Даём загрузиться и встать в позицию, но НЕ pumpAndSettle: анимация
    // вращения бесконечная, и он бы завис.
    // Карта приезжает в состояние через .then → setState. Колбэк поставлен в
    // очередь настоящей асинхронной зоны, и обычный pump его не выполняет —
    // даём ей провернуться, иначе глобус нарисуется вообще без материков.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('sheet')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build').createSync(recursive: true);
        File('build/globe_preview.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  test('у каждой страны приложения есть точка на глобусе', () {
    // Без координат сервер просто не появлялся на глобусе — молча, без ошибки.
    for (final cc in countryCodes) {
      expect(Geo.of(cc), isNotNull, reason: 'нет координат для страны $cc');
    }
  });

  test('названия для подсветки совпадают с картой мира', () {
    // Читаем файл напрямую с диска, а не через rootBundle: проверка не зависит
    // ни от окружения виджетов, ни от порядка тестов.
    final raw = File('assets/geo/world.json').readAsStringSync();
    final names = (jsonDecode(raw) as List)
        .map((c) => (c as Map)['n'] as String)
        .toSet();
    for (final e in Geo.worldName.entries) {
      expect(names, contains(e.value),
          reason: '${e.key}: «${e.value}» нет в world.json — подсветка страны '
              'молча не сработает');
    }
  });
}
