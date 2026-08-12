/// Перетаскивание конфигов: и в полном списке, и в сетке по два в ряд.
///
/// Тест возит палец так же, как человек: зажимает карточку внутри
/// прокручиваемой страницы и ведёт. Именно это раньше и не работало — экран
/// рисовал список двумя разными кусками кода, и без нашей подписки человеку
/// доставалась укороченная копия вообще без перетаскивания. Проверить было
/// нечем: тесты меняли порядок вызовом метода, минуя жест.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/screens/home_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_theme.dart';

VpnServer _srv(String name, String host) => VpnServer(
      protocol: VpnProtocol.vless,
      name: name,
      address: host,
      port: 443,
      raw: 'vless://u@$host:443?security=reality#$name',
      pingMs: 50,
      // Своя (чужая) подписка: с ней конфиги не заблокированы, а значит видны
      // и «⋮», и ручка перетаскивания. Без этого экран рисует платный замок и
      // проверять было бы нечего.
      foreign: true,
    );

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  final s = AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
  s.servers = [
    _srv('Альфа', '203.0.113.1'),
    _srv('Бета', '203.0.113.2'),
    _srv('Гамма', '203.0.113.3'),
  ];
  return s;
}

Future<void> _pump(WidgetTester tester, AppState s, {required bool grid}) async {
  // Глобус на главной анимируется без остановки, поэтому pumpAndSettle тут
  // никогда не вернётся: ждём кадрами.
  s.liteMode = true;
  s.setCompactServers(grid);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Зажимает карточку [from] и ведёт её на место [to] маленькими шагами.
///
/// Сначала удержание, потом движение — ровно как человек. Шагами, а не одним
/// рывком: список живёт внутри прокрутки, и смысл проверки в том, что
/// промежуточные движения не уводят жест в скролл страницы.
Future<void> _dragOnto(WidgetTester tester, Finder from, Finder to) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to);
  final g = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 700)); // удержание
  for (var i = 1; i <= 12; i++) {
    await g.moveTo(Offset.lerp(start, end, i / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  // Несколько кадров, а не один: список доигрывает анимацию посадки карточки и
  // сообщает новый порядок только после неё.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Снимает экран и гасит состояние.
///
/// Именно в таком порядке: у AppState живут таймеры замера, и если снести
/// дерево, не остановив их, тест падает на «остался незакрытый Timer» — уже
/// после того, как всё проверенное прошло.
Future<void> _teardown(WidgetTester tester, AppState s) async {
  await tester.pumpWidget(const SizedBox());
  s.dispose();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('полный список: конфиг переезжает удержанием', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = await _app();
    await _pump(tester, s, grid: false);

    // .last — потому что имя сервера встречается и в шапке экрана; тащить
    // надо карточку из списка.
    await _dragOnto(
        tester, find.text('Альфа').last, find.text('Гамма').last);
    expect(s.servers.first.name, isNot('Альфа'),
        reason: 'первый конфиг обязан уехать вниз');
    await _teardown(tester, s);
  });

  testWidgets('сетка: конфиг переезжает удержанием', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = await _app();
    await _pump(tester, s, grid: true);

    await _dragOnto(
        tester, find.text('Альфа').last, find.text('Бета').last);
    expect(s.servers.first.name, isNot('Альфа'),
        reason: 'ячейка обязана поменяться местами с соседней');
    await _teardown(tester, s);
  });
}
