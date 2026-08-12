/// Рендерит главный экран и «Туннель» в состоянии «человек со своей
/// подпиской» — это состояние показывают покупателю, и увидеть его надо
/// глазами, а не поверить, что «наверное нарисовалось».
///
/// Запуск: flutter test test/foreign_home_render_test.dart
/// Результат: build/screen_foreign_home.png, build/screen_foreign_tunnel.png
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/screens/home_screen.dart';
import 'package:various_vpn/screens/tunnel_settings_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

Future<AppState> _withForeignSub() async {
  SharedPreferences.setMockInitialValues({
    'onboarding_done': true,
    'terms_accepted': true,
  });
  final storage = Storage.instance;
  await storage.resetForTests();
  final s = AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
  s.subLoaded = true;
  s.servers = [
    for (final e in const [
      ('🇩🇪 Германия', '198.51.100.1', 75),
      ('🇨🇭 Швейцария', '198.51.100.2', 93),
      ('🇸🇪 Швеция 1', '198.51.100.3', 66),
    ])
      VpnServer(
        protocol: VpnProtocol.vless,
        name: e.$1,
        address: e.$2,
        port: 443,
        raw: 'vless://u@${e.$2}:443?security=reality&type=tcp#${e.$1}',
        pingMs: e.$3,
        foreign: true,
      ),
  ];
  s.foreignSubUrls = ['https://sub.pager.example/abc'];
  s.foreignUntil = {
    'https://sub.pager.example/abc': DateTime(2026, 8, 8),
  };
  s.foreignInfo = {
    'https://sub.pager.example/abc': const SubInfo(
      title: '📟 Pager VPN',
      until: null,
      used: 1851710847,
      total: 118111600640,
    ),
  };
  return s;
}

Future<void> _shot(WidgetTester tester, String name, Widget screen,
    AppState state) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      // Тему берём базовую тёмную, а не фирменную: фирменная тянет шрифты из
      // сети, которой в тестах нет, и загрузка падает прямо посреди снимка.
      // Цвета экранов заданы палитрой и от темы не зависят — для просмотра
      // вёрстки этого достаточно.
      theme: ThemeData.dark(useMaterial3: true),
      home: RepaintBoundary(key: const ValueKey('shot'), child: screen),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  final b = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')));
  await tester.runAsync(() async {
    final img = await b.toImage(pixelRatio: 1.0);
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/screen_$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      img.dispose();
    }
  });
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('GoogleFonts')) return;
      prev?.call(d);
    };
  });

  // Состояние освобождаем ВНУТРИ теста, а не в addTearDown: конструктор
  // AppState заводит периодический таймер, и проверка «нет висящих таймеров»
  // срабатывает раньше, чем отработает teardown.
  // Переполнения вёрстки ловит screens_smoke_test — там это же состояние
  // проверяется на всех экранах. Здесь задача одна: получить картинку, чтобы
  // посмотреть на экран глазами.
  testWidgets('главная со своей подпиской', (tester) async {
    final s = await _withForeignSub();
    await _shot(tester, 'foreign_home', const HomeScreen(), s);
    tester.takeException(); // шрифты бренда в тестах не грузятся
    s.dispose();
  });

  testWidgets('туннель со своей подпиской — без замков', (tester) async {
    final s = await _withForeignSub();
    final unlocked = s.featuresUnlocked;
    await _shot(tester, 'foreign_tunnel', const TunnelSettingsScreen(), s);
    tester.takeException();
    s.dispose();
    expect(unlocked, isTrue,
        reason: 'со своей подпиской настройки туннеля должны быть открыты');
  });
}
