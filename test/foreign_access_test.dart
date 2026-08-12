/// Что видит человек, пришедший СО СВОЕЙ подпиской другого сервиса.
///
/// Это самый частый сценарий у нового пользователя и главный сценарий показа
/// приложения. Раньше он выглядел сломанным: подписка добавлена и серверы
/// работают, а половина настроек под замком и на главной висит предложение
/// купить — будто приложение подписки не заметило.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

class _FakeApi extends BackendApi {
  _FakeApi(this.body, {this.info});
  final String body;
  final SubInfo? info;

  @override
  Future<String> fetchForeignSubscription(String subUrl,
          {bool Function(String)? isUsable}) async => body;

  @override
  Future<SubInfo?> subInfoFromUrl(String subUrl) async => info;
}

const _sub = 'vless://u@198.51.100.80:443?security=reality#Стокгольм\n'
    'vless://u@198.51.100.81:443?security=reality#Токио';

Future<AppState> _app({SubInfo? info}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
    storage: storage,
    api: _FakeApi(_sub, info: info),
    vpnService: StubVpnService(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('без единой подписки возможности закрыты', () async {
    final s = await _app();
    addTearDown(s.dispose);
    expect(s.featuresUnlocked, isFalse);
    expect(s.hasAccess, isFalse);
  });

  test('своя подписка открывает настройки приложения', () async {
    final s = await _app();
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');

    expect(s.hasForeignServers, isTrue);
    expect(s.featuresUnlocked, isTrue,
        reason: 'тумблеры туннеля работают на любом сервере, запирать нечего');
  });

  test('но к НАШИМ платным серверам она доступа не даёт', () async {
    final s = await _app();
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    expect(s.hasAccess, isFalse,
        reason: 'иначе чужой подпиской открывался бы наш платный доступ');
  });

  test('срок и трафик берутся из ответа этого же сервиса', () async {
    final until = DateTime(2026, 8, 8);
    final s = await _app(
      info: SubInfo(
        title: '📟 Pager VPN',
        until: until,
        used: 1851710847,
        total: 118111600640,
      ),
    );
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    // Запрос сведений фоновый — даём ему завершиться.
    await Future<void>.delayed(Duration.zero);

    final info = s.foreignSubInfo('https://sub.other.example/abc');
    expect(info?.title, '📟 Pager VPN');
    expect(info?.hasTraffic, isTrue);
    expect(s.foreignSubUntil('https://sub.other.example/abc'), until);
  });

  test('после удаления подписки возможности снова закрываются', () async {
    final s = await _app();
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');
    await s.removeForeignSub('https://sub.other.example/abc');

    expect(s.featuresUnlocked, isFalse);
    expect(s.foreignSubInfo('https://sub.other.example/abc'), isNull);
  });

  test('серверы своей подписки выбираются и подключаются', () async {
    final s = await _app();
    addTearDown(s.dispose);
    await s.importFromUrl('https://sub.other.example/abc');

    final own = s.servers.where((e) => e.foreign).toList();
    expect(own, hasLength(2));
    // Автовыбор обязан предложить именно их: наши платные закрыты.
    s.setMode(GlobalMode.ai);
    expect(s.activeServer?.foreign, isTrue);
  });

  test('пробный режим только для Telegram остаётся доступен и без подписок',
      () async {
    final s = await _app();
    addTearDown(s.dispose);
    expect(s.telegramOnly, isFalse);
    // Сам факт отсутствия подписки не должен ломать бесплатный режим —
    // он живёт своим путём и к featuresUnlocked не привязан.
    expect(() => s.setMode(GlobalMode.ai), returnsNormally);
  });
}
