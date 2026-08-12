/// Метод замера пинга: их два, и каждый должен работать и честно
/// подписываться.
///
/// Была тихая ложь: «Точный (TLS)» при неудачном рукопожатии молча возвращал
/// обычный TCP-замер и всё равно помечал результат как точный. В настройках
/// стоял один метод, а число приходило от другого.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/subscription_parser.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('методов ровно два, по умолчанию быстрый', () async {
    final s = await _app();
    addTearDown(s.dispose);
    expect(s.pingType, 'tcp');

    s.pingType = 'proxy';
    expect(s.pingType, 'proxy');
    s.pingType = 'tcp';
    expect(s.pingType, 'tcp');
  });

  test('убранный метод из старых настроек не ломает замер', () async {
    // Пользователь мог выбрать ICMP/HEAD/GET в прошлой сборке. Если оставить
    // это значение как есть, замер ищет несуществующий метод и не запускается
    // вовсе — ровно то, что выглядело как «пинг не работает».
    for (final stale in ['icmp', 'head', 'get', 'мусор']) {
      SharedPreferences.setMockInitialValues({'ping_type': stale});
      final storage = Storage.instance;
      await storage.resetForTests();
      final s = AppState(
          storage: storage, api: BackendApi(), vpnService: StubVpnService());
      expect(s.pingType, 'tcp', reason: 'сохранено «$stale»');
      s.dispose();
    }
  });

  test('смена метода сбрасывает прошлые числа', () async {
    // Иначе часть списка показывает значения прежнего метода, и кажется, что
    // настройка подействовала не на все серверы.
    final s = await _app();
    addTearDown(s.dispose);
    s.servers = [
      VpnServer(
        protocol: VpnProtocol.vless,
        name: 'A',
        address: '198.51.100.95',
        port: 443,
        raw: 'vless://u@198.51.100.95:443?security=reality&sni=a.example#A',
        pingMs: 42,
      )..pingVia = 'tcp',
    ];
    s.pingType = 'proxy';
    expect(s.servers.first.pingMs, lessThanOrEqualTo(0));
    expect(s.servers.first.pingVia, isEmpty);
  });

  group('имя сервера для рукопожатия', () {
    // Точный замер обязан передавать SNI: у Reality адрес обычно голый IP, и
    // без имени рукопожатие не завершается — замер молча падал на TCP.
    test('берётся из ссылки', () {
      final s = SubscriptionParser.parseLink(
          'vless://u@198.51.100.96:443?security=reality&sni=de.example.com#B');
      expect(s!.sni, 'de.example.com');
    });

    test('если имени нет — используем адрес, а не пустоту', () {
      final s = SubscriptionParser.parseLink('trojan://p@node.example:443#C');
      expect(s!.sni, 'node.example');
    });

    test('из списка имён берём первое', () {
      final s = SubscriptionParser.parseLink(
          'vless://u@198.51.100.97:443?host=a.example,b.example#D');
      expect(s!.sni, 'a.example');
    });
  });
}
