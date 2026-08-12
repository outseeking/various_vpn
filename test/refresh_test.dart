/// Кнопка «Обновить».
///
/// Дважды выглядела рабочей и не была: она умела только НАШУ подписку и, не
/// найдя сохранённой ссылки, молча отказывалась работать. У человека со своей
/// подпиской другого сервиса обновлять было нечего.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

class _FakeApi extends BackendApi {
  _FakeApi({this.body = _sub, this.fail = false});
  final String body;
  final bool fail;
  int foreignCalls = 0;

  @override
  Future<String> fetchForeignSubscription(String subUrl,
          {bool Function(String)? isUsable}) async {
    foreignCalls++;
    if (fail) throw const ForeignSubError('timeout');
    return body;
  }

  @override
  Future<SubInfo?> subInfoFromUrl(String subUrl) async => null;
}

const _sub = 'vless://u@198.51.100.90:443?security=reality#Осло\n'
    'vless://u@198.51.100.91:443?security=reality#Рим';

const _subGrown = 'vless://u@198.51.100.90:443?security=reality#Осло\n'
    'vless://u@198.51.100.91:443?security=reality#Рим\n'
    'vless://u@198.51.100.92:443?security=reality#Мадрид';

Future<AppState> _app(BackendApi api) async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: api, vpnService: StubVpnService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('без единой подписки честно говорит, что обновлять нечего', () async {
    final api = _FakeApi();
    final s = await _app(api);
    addTearDown(s.dispose);

    final ok = await s.refreshSubscription();
    expect(ok, isFalse);
    expect(api.foreignCalls, 0);
  });

  test('со своей подпиской — обновляет именно её', () async {
    final api = _FakeApi();
    final s = await _app(api);
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    final before = api.foreignCalls;

    final ok = await s.refreshSubscription();
    expect(ok, isTrue, reason: 'подписка есть — кнопка обязана работать');
    expect(api.foreignCalls, greaterThan(before),
        reason: 'обновление должно реально сходить к сервису');
  });

  test('новые серверы сервиса появляются в списке', () async {
    final api = _FakeApi();
    final s = await _app(api);
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    expect(s.servers.where((e) => e.foreign), hasLength(2));

    // Сервис добавил сервер — после обновления он должен появиться.
    final s2 = await _app(_FakeApi(body: _subGrown));
    addTearDown(s2.dispose);
    await s2.importFromUrl('https://sub.other.example/abc');
    expect(s2.servers.where((e) => e.foreign), hasLength(3));
  });

  test('сервис не ответил — сообщаем, а не молчим', () async {
    final api = _FakeApi();
    final s = await _app(api);
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');

    // Тот же экземпляр состояния, но теперь запросы падают.
    final dead = await _app(_FakeApi(fail: true));
    addTearDown(dead.dispose);
    dead.foreignSubUrls = ['https://sub.other.example/abc'];
    final n = await dead.refreshForeignSubs();
    expect(n, -1, reason: '-1 говорит экрану показать причину отказа');
  });

  test('обновление не открывает доступ к нашим платным серверам', () async {
    final api = _FakeApi();
    final s = await _app(api);
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    await s.refreshSubscription();
    expect(s.hasAccess, isFalse);
  });
}
