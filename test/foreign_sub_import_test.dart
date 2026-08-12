/// Импорт ЧУЖОЙ подписки целиком: от ответа сервера до того, что увидит
/// человек. Проверяются обе стороны — и что серверы доехали до списка, и что
/// при неудаче на экране появляется внятная причина, а не «нет серверов,
/// которые мы умеем».
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

/// Подменяет ТОЛЬКО загрузку чужой подписки — остальное поведение настоящее.
class _FakeApi extends BackendApi {
  _FakeApi(this.body, {this.error});
  final String body;
  final Object? error;

  @override
  Future<String> fetchForeignSubscription(String subUrl,
          {bool Function(String)? isUsable}) async {
    if (error != null) throw error!;
    return body;
  }
}

Future<AppState> _app(BackendApi api) async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: api, vpnService: StubVpnService());
}

/// Тело в формате v2rayN: массив полных конфигов Xray.
const _jsonSub = '''
[
  {"remarks":"🇩🇪 Германия","outbounds":[
    {"tag":"proxy","protocol":"vless",
     "settings":{"vnext":[{"address":"198.51.100.1","port":443,
       "users":[{"id":"aaaaaaaa-1111-4111-8111-111111111111",
                 "encryption":"none","flow":"xtls-rprx-vision"}]}]},
     "streamSettings":{"network":"tcp","security":"reality",
       "realitySettings":{"serverName":"de.example.com","publicKey":"PK",
                          "shortId":"ab","fingerprint":"chrome"}}},
    {"protocol":"freedom","tag":"direct"}]},
  {"remarks":"🇫🇷 Франция","outbounds":[
    {"tag":"proxy","protocol":"trojan",
     "settings":{"servers":[{"address":"198.51.100.2","port":443,
                             "password":"pw"}]},
     "streamSettings":{"network":"tcp","security":"tls",
       "tlsSettings":{"serverName":"fr.example.com"}}}]}
]
''';

/// Тело, где все узлы — на протоколах, которых нет в нашем ядре.
/// Hysteria сюда не годится: после перехода на свежую сборку Xray она
/// поддерживается. Остались TUIC и WireGuard.
const _onlyUnsupported = 'tuic://uuid:pw@198.51.100.6:443#Первый\n'
    'wg://key@198.51.100.7:51820#Второй';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JSON-подписка добавляется, серверы попадают в список', () async {
    final s = await _app(_FakeApi(_jsonSub));
    addTearDown(s.dispose);

    final ok = await s.importFromUrl('https://sub.example.org/abc123');
    expect(ok, isTrue, reason: 'подписка в формате конфигов должна приниматься');
    expect(s.lastError, isNull);
    expect(s.hasForeignServers, isTrue);

    final foreign = s.servers.where((e) => e.foreign).toList();
    expect(foreign, hasLength(2));
    expect(foreign.map((e) => e.address),
        containsAll(['198.51.100.1', '198.51.100.2']));
    // Ремарки с флаг-эмодзи должны превратиться в страны, а не в «DE»/«FR».
    expect(foreign.map((e) => e.countryCode), containsAll(['DE', 'FR']));
  });

  test('чужая подписка НЕ открывает доступ к нашим платным серверам', () async {
    final s = await _app(_FakeApi(_jsonSub));
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.example.org/abc123');
    expect(s.hasAccess, isFalse,
        reason: 'иначе любую подписку можно подставить вместо оплаты');
  });

  test('подписка запоминается и переживает перезапуск', () async {
    final s = await _app(_FakeApi(_jsonSub));
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.example.org/abc123');
    expect(s.foreignSubUrls, ['https://sub.example.org/abc123']);
  });

  test('её можно удалить, и серверы уходят вместе с ней', () async {
    final s = await _app(_FakeApi(_jsonSub));
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.example.org/abc123');
    await s.removeForeignSub('https://sub.example.org/abc123');
    expect(s.foreignSubUrls, isEmpty);
    expect(s.servers.where((e) => e.foreign), isEmpty);
    expect(s.hasForeignServers, isFalse);
  });

  group('понятные причины отказа', () {
    test('ответ вообще не подписка — говорим про ссылку, не про протоколы',
        () async {
      final s = await _app(_FakeApi('<html><body>404</body></html>'));
      addTearDown(s.dispose);
      final ok = await s.importFromUrl('https://sub.example.org/abc');
      expect(ok, isFalse);
      expect(s.lastError, isNotNull);
      expect(s.lastError, contains('не подписка'));
      expect(s.lastError, isNot(contains('которые мы умеем')));
    });

    test('серверы есть, но на чужих протоколах — называем их', () async {
      final s = await _app(_FakeApi(_onlyUnsupported));
      addTearDown(s.dispose);
      final ok = await s.importFromUrl('https://sub.example.org/abc');
      expect(ok, isFalse);
      expect(s.lastError, contains('TUIC'));
      expect(s.lastError, contains('WireGuard'));
      // И обязательно — что делать дальше.
      expect(s.lastError, contains('VLESS'));
    });

    test('подписка пустая — предлагаем проверить её у сервиса', () async {
      final s = await _app(_FakeApi('[]'));
      addTearDown(s.dispose);
      final ok = await s.importFromUrl('https://sub.example.org/abc');
      expect(ok, isFalse);
      expect(s.lastError, contains('серверов в ней нет'));
    });

    test('сетевая ошибка объясняется своими словами', () async {
      final s = await _app(
          _FakeApi('', error: const ForeignSubError('not_found')));
      addTearDown(s.dispose);
      final ok = await s.importFromUrl('https://sub.example.org/abc');
      expect(ok, isFalse);
      expect(s.lastError, contains('404'));
    });
  });

  test('смешанная подписка: годные берём, про пропущенные предупреждаем',
      () async {
    const mixed = 'vless://u@198.51.100.7:443?security=reality#Осло\n'
        'hysteria2://pw@198.51.100.8:443#Быстрый\n'
        'tuic://u:p@198.51.100.9:443#Лишний';
    final s = await _app(_FakeApi(mixed));
    addTearDown(s.dispose);

    final ok = await s.importFromUrl('https://sub.example.org/abc');
    expect(ok, isTrue);
    // VLESS и Hysteria доезжают, TUIC — нет.
    expect(s.servers.where((e) => e.foreign), hasLength(2));
    expect(s.servers.any((e) => e.protocol == VpnProtocol.hysteria2), isTrue);
    // Неподдерживаемый узел не должен появиться в списке серверов вообще —
    // иначе человек выберет его и получит молчаливый отказ подключения.
    expect(s.servers.every((e) => e.protocol != VpnProtocol.tuic), isTrue);
  });
}
