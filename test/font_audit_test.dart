/// Аудит шрифта: весь текст приложения обязан рисоваться выбранным шрифтом.
///
/// Проверка нужна потому, что промах здесь незаметен глазу разработчика:
/// TextStyle без fontFamily не «наследует» шрифт темы, а откатывается на
/// системный. На экране это выглядит просто «чуть другой буквой» — и живёт
/// годами.
///
/// Тест поднимает настоящие экраны, обходит дерево и смотрит РЕЗУЛЬТИРУЮЩИЙ
/// стиль каждой надписи: именно то, что увидит человек.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/screens/connection_settings_screen.dart';
import 'package:various_vpn/screens/network_settings_screen.dart';
import 'package:various_vpn/screens/ping_settings_screen.dart';
import 'package:various_vpn/screens/profile_screen.dart';
import 'package:various_vpn/screens/settings_screen.dart';
import 'package:various_vpn/screens/subscriptions_screen.dart';
import 'package:various_vpn/screens/support_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_fonts.dart';
import 'package:various_vpn/theme/app_theme.dart';

/// Семейства, которым позволено отличаться от выбранного шрифта.
///
/// Моноширинный — единственное исключение: им показывают сырой конфиг, где
/// важно, чтобы символы стояли столбиком.
const _allowed = {'monospace'};

/// Семейство шрифта без указания начертания.
///
/// google_fonts кодирует вес прямо в имени семейства: Exo2_regular, Exo2_700,
/// Exo2_800 — это один и тот же шрифт. Сравнивать надо основу, иначе жирный
/// заголовок выглядит «чужим шрифтом», хотя он свой.
String _family(String? full) => (full ?? '').split('_').first;

/// Основа семейства выбранного шрифта.
String get _expected =>
    _family(AppFonts.byKey(AppFonts.defaultKey).style(const TextStyle())
        .fontFamily);

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  final s = AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
  s.liteMode = true;
  s.servers = [
    VpnServer(
      protocol: VpnProtocol.vless,
      name: 'Германия',
      address: '203.0.113.1',
      port: 443,
      raw: 'vless://u@203.0.113.1:443?security=reality#Германия',
      pingMs: 74,
      foreign: true,
    ),
  ];
  return s;
}

/// Собирает семейства шрифтов всех надписей на экране.
Set<String> _families(WidgetTester tester) {
  final out = <String>{};
  for (final element in find.byType(Text).evaluate()) {
    final w = element.widget as Text;
    // Ровно так стиль собирает и сам Flutter при отрисовке: стиль виджета
    // поверх стиля по умолчанию из окружения.
    final def = DefaultTextStyle.of(element);
    final style = w.style == null
        ? def.style
        : (w.style!.inherit ? def.style.merge(w.style) : w.style!);
    out.add(style.fontFamily == null
        ? '(системный по умолчанию)'
        : _family(style.fontFamily));
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = <String, Widget Function()>{
    'Настройки': () => const SettingsScreen(),
    'Профиль': () => const ProfileScreen(),
    'Подписки': () => const SubscriptionsScreen(),
    'Поддержка': () => const SupportScreen(),
    'Пинг': () => const PingSettingsScreen(),
    'Подключение': () => const ConnectionSettingsScreen(),
    'Сеть': () => const NetworkSettingsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key}: весь текст выбранным шрифтом', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final s = await _app();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(builder: (_) => entry.value()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final found = _families(tester)
        ..removeWhere((f) => _allowed.contains(f) || f == _expected);

      expect(found, isEmpty,
          reason: 'на экране «${entry.key}» есть текст чужим шрифтом: $found\n'
              'Ожидался $_expected. Причина почти всегда одна: TextStyle без '
              'fontFamily в теме — он не наследует шрифт, а берёт системный.');

      await tester.pumpWidget(const SizedBox());
      s.dispose();
      await tester.pump();
    });
  }

  _themeStyles();
}

/// Отдельная проверка на стили, заданные в теме целиком.
///
/// Такой стиль компонент не «домешивает» к теме, а ПОДМЕНЯЕТ им стандартный.
/// Значит, TextStyle без fontFamily в теме — это не «наследую шрифт», а
/// «беру системный». Плоский Text этим не проверить: беда вылезает только в
/// меню, диалогах и кнопках.
void _themeStyles() {
  test('стили из темы заданы выбранным шрифтом', () {
    final theme = AppTheme.dark();

    final checks = <String, TextStyle?>{
      'popupMenuTheme.textStyle': theme.popupMenuTheme.textStyle,
      'dialogTheme.titleTextStyle': theme.dialogTheme.titleTextStyle,
      'dialogTheme.contentTextStyle': theme.dialogTheme.contentTextStyle,
      'snackBarTheme.contentTextStyle': theme.snackBarTheme.contentTextStyle,
      'elevatedButtonTheme.textStyle': theme.elevatedButtonTheme.style?.textStyle
          ?.resolve(<WidgetState>{}),
    };

    final bad = <String>[];
    checks.forEach((name, style) {
      if (style != null && _family(style.fontFamily) != _expected) {
        bad.add('$name (${style.fontFamily ?? "без шрифта"})');
      }
    });
    expect(bad, isEmpty,
        reason: 'эти стили темы подменяют шрифт системным: $bad');
  });
}
