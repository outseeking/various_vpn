/// Режим «ИИ»: выбор сервера и срок чужой подписки.
///
/// Проверяется то, из-за чего режим выглядел неработающим: ИИ брал не самый
/// быстрый сервер, а как будто случайный, и рядом с чужой подпиской
/// показывалась дата нашей.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

VpnServer _srv(String host, {int ping = -1, String extra = '', bool dead = false}) {
  final s = VpnServer(
    protocol: VpnProtocol.vless,
    name: host,
    address: host,
    port: 443,
    raw: 'vless://u@$host:443?$extra#$host',
    pingMs: ping,
    foreign: true,
  );
  if (dead) s.unreachable = true;
  return s;
}

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ИИ выбирает сервер', () {
    test('берёт самый быстрый по пингу', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.1', ping: 210, extra: 'security=reality'),
        _srv('203.0.113.2', ping: 45, extra: 'security=reality'),
        _srv('203.0.113.3', ping: 130, extra: 'security=reality'),
      ];
      s.setMode(GlobalMode.ai);
      expect(s.activeServer?.address, '203.0.113.2');
    });

    test('измеренный сервер важнее неизмеренного, даже с лучшим транспортом',
        () async {
      // Здесь ИИ и выглядел «случайным»: Reality без замера обгонял живой
      // TLS-сервер с отличным пингом только потому, что транспорт надёжнее.
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.10', extra: 'security=reality'), // пинг неизвестен
        _srv('203.0.113.11', ping: 20, extra: 'security=tls&type=tcp'),
      ];
      s.setMode(GlobalMode.ai);
      expect(s.activeServer?.address, '203.0.113.11');
    });

    test('при близких пингах выигрывает надёжный транспорт', () async {
      // Надбавка за транспорт небольшая — она решает только «при прочих
      // равных» и не должна перебивать реальную разницу в скорости.
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.20', ping: 50, extra: 'security=tls&type=ws'),
        _srv('203.0.113.21', ping: 55, extra: 'security=reality'),
      ];
      s.setMode(GlobalMode.ai);
      expect(s.activeServer?.address, '203.0.113.21');
    });

    test('сервер, признанный нерабочим, не выбирается', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.30', ping: 10, extra: 'security=reality', dead: true),
        _srv('203.0.113.31', ping: 300, extra: 'security=reality'),
      ];
      s.setMode(GlobalMode.ai);
      expect(s.activeServer?.address, '203.0.113.31');
    });

    test('порядок серверов, заданный человеком, не переставляется', () async {
      // Раньше подбор «лучшего» сортировал сам список серверов — и карточки
      // на главной самопроизвольно менялись местами.
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.40', ping: 300, extra: 'security=reality'),
        _srv('203.0.113.41', ping: 20, extra: 'security=reality'),
      ];
      s.setMode(GlobalMode.ai);
      s.activeServer; // сам факт обращения не должен ничего менять
      expect(s.servers.map((e) => e.address),
          ['203.0.113.40', '203.0.113.41']);
    });

    test('в ручном режиме выбор человека сильнее любого пинга', () async {
      final s = await _app();
      addTearDown(s.dispose);
      s.servers = [
        _srv('203.0.113.50', ping: 20, extra: 'security=reality'),
        _srv('203.0.113.51', ping: 400, extra: 'security=reality'),
      ];
      // Берём НАСТОЯЩИЙ id сервера: он включает подпись конфига, поэтому
      // собирать его строкой в тесте нельзя.
      s.setManualServer(s.servers.last.id);
      s.setMode(GlobalMode.manual);
      expect(s.activeServer?.address, '203.0.113.51');
    });
  });

  group('срок чужой подписки', () {
    test('хранится отдельно от нашей и переживает перезапуск', () async {
      final until = DateTime(2026, 9, 1);
      SharedPreferences.setMockInitialValues({
        'foreign_subs': 'https://other.example/abc',
        'foreign_until':
            'https://other.example/abc\t${until.millisecondsSinceEpoch}',
      });
      final storage = Storage.instance;
      await storage.resetForTests();
      final s = AppState(
          storage: storage, api: BackendApi(), vpnService: StubVpnService());
      addTearDown(s.dispose);
      // Настройки читаются не в конструкторе, а в bootstrap — как при запуске.
      await s.bootstrap();

      expect(s.foreignSubUrls, ['https://other.example/abc']);
      expect(s.foreignSubUntil('https://other.example/abc'), until);
      // И главное: на НАШУ подписку это не влияет — доступ к платным серверам
      // чужой датой не открывается.
      expect(s.hasAccess, isFalse);
    });

    test('у неизвестной подписки даты нет, а не наша', () async {
      final s = await _app();
      addTearDown(s.dispose);
      expect(s.foreignSubUntil('https://never.example/x'), isNull);
    });
  });
}
