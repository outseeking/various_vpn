/// Список серверов: свой порядок, перетаскивание и уникальность конфигов.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/subscription_parser.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

VpnServer _srv(String host, {int ping = -1, String name = ''}) => VpnServer(
      protocol: VpnProtocol.vless,
      name: name.isEmpty ? host : name,
      address: host,
      port: 443,
      raw: 'vless://u@$host:443?security=reality#$host',
      pingMs: ping,
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

  group('перетаскивание', () {
    test('во время перетаскивания список не перерисовывается', () async {
      // Каждая перерисовка срывала захват карточки, и переставить конфиг во
      // время фонового замера было невозможно.
      final s = await _app();
      addTearDown(s.dispose);
      var rebuilds = 0;
      s.addListener(() => rebuilds++);

      s.setListDragging(true);
      final during = rebuilds;
      s.servers = [_srv('203.0.113.8', ping: 50)];
      // Уведомления от замера подавлены: проверяем именно их источник.
      expect(rebuilds, during, reason: 'во время таскания тишина');

      s.setListDragging(false);
      expect(rebuilds, greaterThan(during),
          reason: 'после отпускания показываем накопленное');
    });

    test('порядок меняется и сохраняется', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.10'),
        _srv('203.0.113.11'),
        _srv('203.0.113.12'),
      ];
      s.reorderServers(0, 3); // первый — в конец
      expect(s.servers.map((e) => e.address),
          ['203.0.113.11', '203.0.113.12', '203.0.113.10']);
    });
  });

  group('идентификатор сервера', () {
    // В подписках несколько записей нередко ведут на ОДИН хост и порт,
    // отличаясь транспортом или ключом. При id без учёта конфига они
    // совпадали — и ломалось всё, что на него опирается.
    test('разные конфиги на одном адресе получают разные id', () {
      final a = SubscriptionParser.parseLink(
          'vless://u1@198.51.100.50:443?security=reality&type=tcp#Wi-Fi 2');
      final b = SubscriptionParser.parseLink(
          'vless://u1@198.51.100.50:443?security=reality&type=grpc#Wi-Fi 5');
      final c = SubscriptionParser.parseLink(
          'vless://u2@198.51.100.50:443?security=reality&type=tcp#Wi-Fi 6');
      expect(a!.id, isNot(b!.id), reason: 'разный транспорт — разные серверы');
      expect(a.id, isNot(c!.id), reason: 'разный ключ — разные серверы');
    });

    test('один и тот же конфиг даёт один и тот же id между запусками', () {
      const link = 'vless://u@198.51.100.51:443?security=reality#A';
      expect(SubscriptionParser.parseLink(link)!.id,
          SubscriptionParser.parseLink(link)!.id);
    });

    test('в списке из подписки все id уникальны', () {
      const body = 'vless://u@198.51.100.52:443?type=tcp#A\n'
          'vless://u@198.51.100.52:443?type=grpc#B\n'
          'trojan://p@198.51.100.52:443#C';
      final servers = SubscriptionParser.parseDetailed(body).servers;
      final ids = servers.map((e) => e.id).toSet();
      expect(ids, hasLength(servers.length),
          reason: 'одинаковые ключи ломают список и перетаскивание');
    });
  });
}
