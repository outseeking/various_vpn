/// Рендерит проблемные экраны в PNG, чтобы увидеть глазами, что не помещается.
///
/// Сообщение «RenderFlex overflowed by N pixels» не называет виновника, если
/// ошибка всплыла после снятия дерева. Картинка называет: место переполнения
/// Flutter помечает жёлто-чёрной штриховкой.
///
/// Запуск: flutter test test/screens_render_test.dart
/// Результат: build/screen_<имя>.png
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
import 'package:various_vpn/screens/connect_guide_screen.dart';
import 'package:various_vpn/screens/per_app_screen.dart';
import 'package:various_vpn/screens/profile_screen.dart';
import 'package:various_vpn/screens/servers_screen.dart';
import 'package:various_vpn/screens/subscriptions_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_theme.dart';

final _targets = <String, Widget Function()>{
  'subscriptions': () => const SubscriptionsScreen(),
  'profile': () => const ProfileScreen(),
  'guide': () => const ConnectGuideScreen(),
  'servers': () => const ServersScreen(),
  'perapp': () => const PerAppScreen(),
};

void main() {
  // Шрифты в тестах не качаем: сеть в тестовой среде заблокирована, и попытка
  // загрузки роняет тест — это не дефект интерфейса, а особенность окружения.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('GoogleFonts')) return;
      prev?.call(d);
    };
  });

  for (final e in _targets.entries) {
    testWidgets('рендер ${e.key}', (tester) async {
      // Узкий телефон 360dp — на нём и вылезают переполнения.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({'tg_id': '1658245753'});
      final storage = Storage.instance;
      await storage.init();
      final state = AppState(
        storage: storage,
        api: BackendApi(),
        vpnService: StubVpnService(),
      );
      state.subActive = true;
      state.subLoaded = true;
      state.subUntil = DateTime.now().add(const Duration(days: 9));
      state.servers = [
        VpnServer(
          protocol: VpnProtocol.vless,
          name: '🇳🇱 Нидерланды',
          address: '89.125.17.116',
          port: 443,
          raw: 'vless://u@89.125.17.116:443?security=reality&type=tcp#NL',
          pingMs: 534,
        ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: RepaintBoundary(key: const ValueKey('s'), child: e.value()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final boundary = tester
          .renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('s')));
      final img = await boundary.toImage(pixelRatio: 1.6);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/screen_${e.key}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());

      state.dispose();
    }, timeout: const Timeout(Duration(seconds: 25)));
  }
}
