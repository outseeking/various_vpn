/// Аудит логики: правила, которые обязаны выполняться всегда.
///
/// Это не проверка отдельных функций, а свод обещаний приложения. Каждое из
/// них уже было однажды нарушено, и каждое нарушение стоило дня разбирательств.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/subscription_parser.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

VpnServer _srv({bool foreign = false, String host = '203.0.113.1'}) =>
    VpnServer(
      protocol: VpnProtocol.vless,
      name: 'Тест',
      address: host,
      port: 443,
      raw: 'vless://u@$host:443?security=reality#Тест',
      foreign: foreign,
    );

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('доступ', () {
    test('чужая подписка открывает функции без нашей оплаты', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [_srv(foreign: true)];
      expect(s.hasAccess, isFalse, reason: 'нашей подписки нет');
      expect(s.featuresUnlocked, isTrue,
          reason: 'но приложение обязано работать как обычный VPN-клиент');
    });

    test('без подписок функции закрыты', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [_srv()];
      expect(s.featuresUnlocked, isFalse);
    });
  });

  group('замер задержки', () {
    test('интервал не опускается ниже 30 секунд', () async {
      // Полный проход по списку занимает несколько секунд. На интервале
      // меньше 30 приложение почти всё время меряет и жжёт батарею.
      final s = await _app();
      addTearDown(s.dispose);
      s.pingEveryS = 5;
      expect(s.pingEveryS, greaterThanOrEqualTo(30));
    });

    test('«не мерить» сохраняется как есть', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.pingEveryS = 0;
      expect(s.pingEveryS, 0, reason: 'ноль — это выключено, а не «мало»');
    });
  });

  group('разбор подписки', () {
    test('сервер без адреса не попадает в список', () {
      // Панель, отказывая клиенту, отвечает подпиской из одного конфига на
      // 0.0.0.0 — формально валидного, но несуществующего.
      const body = 'vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1#Нет';
      expect(SubscriptionParser.parseDetailed(body).usable, isEmpty);
    });

    test('одинаковые адреса с разным транспортом — разные серверы', () {
      final a = SubscriptionParser.parseLink(
          'vless://u@198.51.100.5:443?security=reality&type=tcp#A');
      final b = SubscriptionParser.parseLink(
          'vless://u@198.51.100.5:443?security=reality&type=grpc#B');
      expect(a!.id, isNot(b!.id),
          reason: 'иначе ломается и выбор, и перетаскивание');
    });
  });

  group('порядок серверов', () {
    test('переживает обновление списка', () async {
      // Обновление подписки пересобирает servers с нуля. Если порядок не
      // применить заново, расстановка человека пропадает при каждом обновлении.
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv(host: '203.0.113.1'),
        _srv(host: '203.0.113.2'),
        _srv(host: '203.0.113.3'),
      ];
      s.reorderServers(0, 3);
      final after = s.servers.map((e) => e.address).toList();

      // Тот же набор приходит заново, в исходном порядке.
      s.servers = [
        _srv(host: '203.0.113.1'),
        _srv(host: '203.0.113.2'),
        _srv(host: '203.0.113.3'),
      ];
      expect(s.servers.map((e) => e.address).toList(), after,
          reason: 'порядок человека важнее порядка подписки');
    });
  });
}
