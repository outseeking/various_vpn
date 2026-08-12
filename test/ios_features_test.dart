/// Что из функций Android реально доехало до iOS.
///
/// Проверять это на словах бессмысленно: раздел может «быть», но открываться
/// пустым, а правила маршрутизации — молча вырезаться из конфига, и человек
/// увидит лишь то, что VPN работает как-то не так. Поэтому здесь всё
/// проверяется тем же способом, каким это увидит пользователь: экран
/// открывают, конфиг собирают и смотрят, что внутри.
///
/// Платформа подменяется через debugDefaultTargetPlatformOverride — тот же
/// признак, по которому её определяет и сам код (lib/platform.dart).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/l10n.dart';
import 'package:various_vpn/platform.dart';
import 'package:various_vpn/screens/per_app_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/services/xray_config.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_theme.dart';

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
}

/// Минимальный конфиг — тот же приём, что и в остальных тестах ядра: важно не
/// содержимое, а что с ним сделают правила.
String _baseConfig() => jsonEncode({
      'outbounds': [
        {'protocol': 'vless', 'tag': 'proxy', 'streamSettings': {}},
      ],
      'routing': {'rules': []},
    });

void main() {
  // Подмену платформы включает каждый тест сам и сам же снимает. Общий setUp
  // здесь не годится: проверка виджетов следит за отладочными переключателями
  // и считает оставленный включённым признак ошибкой теста.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Признаки платформы: на iOS доступно всё, кроме списка приложений', () {
    // Списка установленных программ система не отдаёт — это ограничение Apple,
    // а не недоделка, и оно должно остаться единственным.
    expect(Caps.perAppRouting, isFalse);

    // Остальное перенесено и обязано быть включено. Если кто-то однажды
    // выключит любое из этого «на всякий случай», тест не даст пройти молча.
    expect(Caps.geoAssets, isTrue,
        reason: 'geo-списки кладутся в ресурсы расширения на сборке');
    expect(Caps.appIconSwitch, isTrue,
        reason: 'запасные значки лежат в бандле, переключает система');
    expect(Caps.vpnTunnel, isTrue);
  });

  test('Правила маршрутизации на iOS остаются в конфиге', () {
    final cfg = applyNetOptions(
      _baseConfig(),
      const NetOptions(
        bypassRu: true,
        adBlock: true,
        directDomains: ['sberbank.ru'],
      ),
    );

    // Раньше на iOS все ссылки на списки вырезались: файлов в бандле не было, а
    // с неизвестным списком Xray не «пропускает правило», а вовсе не стартует.
    // Теперь файлы на месте — значит и правила обязаны остаться.
    expect(cfg, contains('geosite:'),
        reason: 'без geosite перестаёт работать блокировка рекламы и обходы');
    expect(cfg, contains('sberbank.ru'),
        reason: 'правила по сайтам работают на обеих системах');
  });

  testWidgets('Раздел маршрутов на iOS открывается и содержит правила по сайтам',
      (tester) async {
    final state = await _app();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const PerAppScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    // Экран уже построен по iOS-ветке, дальше признак не нужен — снимаем его
    // до конца теста, иначе проверка виджетов сочтёт его забытым.
    debugDefaultTargetPlatformOverride = null;

    // Заголовок — про сайты, а не про приложения: обещать список программ,
    // которого система не даёт, нельзя.
    expect(find.text(L.t('tab_urls')), findsWidgets);
    expect(find.text(L.t('tab_apps')), findsNothing);

    // Состояние заводит свои таймеры (пинги, замеры). Снимаем дерево и гасим
    // его явно — иначе проверка виджетов упрётся в незакрытый таймер.
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
