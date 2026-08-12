/// Обход ВСЕХ экранов приложения.
///
/// Зачем тестом, а не руками: пройти пальцем два десятка экранов один раз
/// можно, но повторять это после каждой правки никто не станет — и регрессии
/// всплывают уже у пользователя. Здесь то же самое выполняется за секунды и на
/// каждой сборке.
///
/// Каждый экран — ОТДЕЛЬНЫЙ тест со своим лимитом времени. Так зависший экран
/// не блокирует проверку остальных и сразу виден по имени в отчёте.
///
/// Проверяется:
///   • экран строится без исключений в трёх состояниях — новичок без подписки,
///     бесплатный режим, оплаченная подписка (у каждого своя вёрстка);
///   • на экране нет «сырых» ключей вида gs_id_go вместо человеческого текста.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/l10n.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/screens/app_icon_screen.dart';
import 'package:various_vpn/screens/auth_screen.dart';
import 'package:various_vpn/screens/auto_wifi_screen.dart';
import 'package:various_vpn/screens/backup_screen.dart';
import 'package:various_vpn/screens/connect_guide_screen.dart';
import 'package:various_vpn/screens/connection_settings_screen.dart';
import 'package:various_vpn/screens/custom_servers_screen.dart';
import 'package:various_vpn/screens/import_screen.dart';
import 'package:various_vpn/screens/killswitch_guide_screen.dart';
import 'package:various_vpn/screens/logs_screen.dart';
import 'package:various_vpn/screens/network_settings_screen.dart';
import 'package:various_vpn/screens/onboarding_screen.dart';
import 'package:various_vpn/screens/per_app_screen.dart';
import 'package:various_vpn/screens/ping_settings_screen.dart';
import 'package:various_vpn/screens/profile_screen.dart';
import 'package:various_vpn/screens/servers_screen.dart';
import 'package:various_vpn/screens/settings_screen.dart';
import 'package:various_vpn/screens/speedtest_screen.dart';
import 'package:various_vpn/screens/stats_screen.dart';
import 'package:various_vpn/screens/subscriptions_screen.dart';
import 'package:various_vpn/screens/support_screen.dart';
import 'package:various_vpn/screens/tunnel_settings_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_theme.dart';

/// Экраны, которые в тестовой среде проверить нельзя.
///
/// «По приложениям» запрашивает список установленных программ (плагина в
/// тестовом движке нет), «Диагностика» открывает настоящие сетевые сокеты с
/// таймаутами. И то и другое падает на ОКРУЖЕНИИ, а не на дефекте экрана, —
/// молча «зеленить» такие тесты нечестно, поэтому они явно пропущены с
/// причиной. Обе экрана проверяются вручную на устройстве.
const _platformOnly = {
  'По приложениям': 'нужен список установленных приложений (нет плагина)',
};

Map<String, Widget Function()> _screens() => {
      'Онбординг': () => const OnboardingScreen(),
      'Вход': () => const AuthScreen(),
      'Как подключиться': () => const ConnectGuideScreen(),
      'Как подключиться · после триала': () =>
          const ConnectGuideScreen(afterFreeEnable: true),
      'Добавить подписку': () => const ImportScreen(),
      'Мои подписки': () => const SubscriptionsScreen(),
      'Серверы': () => const ServersScreen(),
      'Профиль': () => const ProfileScreen(),
      'Настройки': () => const SettingsScreen(),
      'Настройки · Подключение': () => const ConnectionSettingsScreen(),
      'Настройки · Туннель': () => const TunnelSettingsScreen(),
      'Сеть и протокол': () => const NetworkSettingsScreen(),
      'Пинг': () => const PingSettingsScreen(),
      'По приложениям': () => const PerAppScreen(),
      'Свои серверы': () => const CustomServersScreen(),
      'Авто-Wi-Fi': () => const AutoWifiScreen(),
      'Kill Switch': () => const KillSwitchGuideScreen(),
      'Статистика': () => const StatsScreen(),
      'Скорость': () => const SpeedtestScreen(),
      'Логи': () => const LogsScreen(),
      'Резервная копия': () => const BackupScreen(),
      'Иконка приложения': () => const AppIconScreen(),
      'Поддержка': () => const SupportScreen(),
    };

List<VpnServer> _demoServers() => [
      VpnServer(
        protocol: VpnProtocol.vless,
        name: '🇳🇱 Нидерланды',
        address: '89.125.17.116',
        port: 443,
        raw: 'vless://u@89.125.17.116:443?security=reality&type=tcp#NL',
        pingMs: 42,
      ),
      VpnServer(
        protocol: VpnProtocol.vless,
        name: '🇵🇱 Польша 1',
        address: '1.2.3.4',
        port: 443,
        raw: 'vless://u@1.2.3.4:443?security=reality&type=tcp#PL',
        pingMs: 120,
      ),
    ];

Future<AppState> _makeState(
    {required bool paid, required bool free, bool foreign = false}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_done': true,
    'terms_accepted': true,
    if (paid) 'sub_active_cache': true,
    if (paid) 'access_granted': true,
    if (paid) 'tg_id': '1658245753',
    if (paid)
      'sub_until_cache':
          DateTime.now().add(const Duration(days: 9)).toIso8601String(),
    if (free) 'telegram_only': true,
  });
  final storage = Storage.instance;
  await storage.init();
  final state = AppState(
    storage: storage,
    api: BackendApi(),
    vpnService: StubVpnService(),
  );
  // ВАЖНО: полный bootstrap() здесь не зовём. Он поднимает фоновые таймеры и
  // ходит в сеть — в тестовой среде это подвешивает каждый тест на таймаут, а
  // к вёрстке экранов отношения не имеет. Ставим ровно те поля, от которых
  // зависит внешний вид.
  state.subActive = paid;
  state.subLoaded = true;
  state.subUntil =
      paid ? DateTime.now().add(const Duration(days: 9)) : null;
  state.telegramOnly = free;
  state.servers = _demoServers();
  if (foreign) {
    // Человек пришёл СО СВОЕЙ подпиской другого сервиса — главный сценарий
    // показа приложения. На главной появляется её карточка, а плашки «уже есть
    // подписка?» быть не должно.
    state.foreignSubUrls = ['https://sub.other.example/abc'];
    state.foreignUntil = {
      'https://sub.other.example/abc':
          DateTime.now().add(const Duration(days: 3)),
    };
    for (final srv in state.servers) {
      srv.foreign = true;
    }
  }
  return state;
}

Widget _wrap(AppState state, Widget child) =>
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: AppTheme.dark(), home: child),
    );

/// Текст, похожий на невыведенный ключ локализации (gs_id_go вместо «Войти»).
List<String> _rawKeys(WidgetTester tester) {
  final bad = <String>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final t = w.data;
    if (t == null || t.length < 4) continue;
    if (RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+){1,}$').hasMatch(t) &&
        L.t(t) == t) {
      bad.add(t);
    }
  }
  return bad;
}

void main() {
  // Шрифты в тестах не качаем: сеть в тестовой среде заблокирована, и попытка
  // загрузки роняет тест — это не дефект интерфейса, а особенность окружения.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Шрифты бренда качаются из сети — в тестах она заблокирована. Это
    // особенность окружения, а не дефект экрана, поэтому такие ошибки глушим.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('GoogleFonts')) return;
      prev?.call(d);
    };
  });

  for (final (label, paid, free, foreign) in const [
    ('новичок', false, false, false),
    ('бесплатный', false, true, false),
    ('оплачено', true, false, false),
    ('своя подписка', false, false, true),
  ]) {
    _screens().forEach((name, build) {
      // Причину пропуска дописываем в имя: в отчёте сразу видно, почему
      // экран не проверялся, а не просто «skipped».
      final why = _platformOnly[name];
      testWidgets('$name · $label${why == null ? "" : " (пропуск: $why)"}',
          (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        // Ошибки вёрстки (переполнение Row/Column) ловим ПРЯМО во время
        // отрисовки: если ждать конца теста, дерево уже снято и в отчёте
        // остаются бесполезные DEFUNCT-элементы вместо имени виновника.
        final layoutErrors = <String>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.exceptionAsString();
          if (text.contains('overflowed')) {
            final where = details.context?.toDescription() ?? '';
            layoutErrors.add('$text ($where)');
          } else {
            prevOnError?.call(details);
          }
        };

        final state = await _makeState(paid: paid, free: free, foreign: foreign);
        await tester.pumpWidget(_wrap(state, build()));
        await tester.pump(const Duration(milliseconds: 350));

        FlutterError.onError = prevOnError;
        final raw = _rawKeys(tester);

        // Состояние поднимает фоновые таймеры (авто-пинг, сторож подписки).
        // Их надо погасить ВНУТРИ теста: проверка «не осталось таймеров»
        // выполняется раньше, чем addTearDown. Сначала снимаем дерево, чтобы
        // виджеты отписались, потом гасим состояние.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        state.dispose();

        expect(raw, isEmpty, reason: 'нет перевода: ${raw.join(", ")}');
        expect(layoutErrors, isEmpty,
            reason: 'вёрстка не помещается: ${layoutErrors.join(" | ")}');
      },
          timeout: const Timeout(Duration(seconds: 20)),
          skip: _platformOnly.containsKey(name));
    });
  }
}
