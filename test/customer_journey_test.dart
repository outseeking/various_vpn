/// Путь покупателя целиком: от первого запуска до продления.
///
/// Проверяется НЕ вёрстка, а логика доступа — то, из-за чего теряются деньги:
/// открылся ли VPN тому, кто не платил; закрылся ли, когда подписка кончилась;
/// вернулся ли доступ после продления. Каждый шаг — отдельная проверка, чтобы
/// в отчёте было видно, какой именно участок пути сломался.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

/// Наш платный сервер (панель) и сервер чужого сервиса.
VpnServer _ours() => VpnServer(
      protocol: VpnProtocol.vless,
      name: '🇳🇱 Нидерланды',
      address: '89.125.17.116',
      port: 443,
      raw: 'vless://u@89.125.17.116:443?security=reality&type=tcp#NL',
      pingMs: 42,
    );

VpnServer _foreign() => VpnServer(
      protocol: VpnProtocol.vless,
      name: '🇵🇱 Своя Польша',
      address: '203.0.113.9',
      port: 443,
      raw: 'vless://u@203.0.113.9:443?security=reality&type=tcp#PL',
      pingMs: 90,
      foreign: true,
    );

Future<AppState> _fresh(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = Storage.instance;
  // Хранилище — синглтон: без сброса следующий сценарий получил бы настройки
  // предыдущего, и проверки доступа стали бы бессмысленными.
  await storage.resetForTests();
  return AppState(
    storage: storage,
    api: BackendApi(),
    vpnService: StubVpnService(),
  );
}

void main() {
  // Состояние приложения трогает платформенные каналы (сеть, хранилище),
  // поэтому окружение нужно поднять до первого теста.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1. первый запуск: доступа нет, платить не за что', () async {
    final s = await _fresh({});
    addTearDown(s.dispose);
    expect(s.hasAccess, isFalse, reason: 'новичку VPN открыт быть не должен');
    expect(s.hasForeignServers, isFalse);
    expect(s.subActive, isFalse);
  });

  test('2. бесплатный режим не считается оплаченным доступом', () async {
    final s = await _fresh({'telegram_only': true});
    addTearDown(s.dispose);
    s.telegramOnly = true;
    expect(s.hasAccess, isFalse,
        reason: 'бесплатный Telegram не должен открывать платные настройки');
  });

  test('3. подписка активна → доступ открыт', () async {
    final until = DateTime.now().add(const Duration(days: 9));
    final s = await _fresh({
      'sub_active_cache': true,
      'sub_until_cache': until.toIso8601String(),
      'access_granted': true,
      'tg_id': '1658245753',
    });
    addTearDown(s.dispose);
    await s.bootstrap();
    expect(s.hasAccess, isTrue, reason: 'оплатившему доступ обязан открыться');
    expect(s.subUntil, isNotNull, reason: 'дата окончания должна быть известна');
  });

  test('4. подписка кончилась → доступ закрывается даже офлайн', () async {
    final past = DateTime.now().subtract(const Duration(days: 1));
    final s = await _fresh({
      'sub_active_cache': true,
      'sub_until_cache': past.toIso8601String(),
      'access_granted': true, // «вечный» флаг из прошлого запуска
      'tg_id': '1658245753',
    });
    addTearDown(s.dispose);
    await s.bootstrap();
    expect(s.hasAccess, isFalse,
        reason: 'просроченная подписка не должна открывать VPN офлайн');
  });

  test('5. продление возвращает доступ', () async {
    final s = await _fresh({'tg_id': '1658245753'});
    addTearDown(s.dispose);
    await s.bootstrap();
    expect(s.hasAccess, isFalse);
    // Оплата в боте → приложение узнаёт новый срок и открывает доступ.
    s.subActive = true;
    s.subUntil = DateTime.now().add(const Duration(days: 30));
    expect(s.hasAccess, isTrue, reason: 'после продления доступ обязан вернуться');
  });

  test('6. без подписки наши серверы недоступны, свои — работают', () async {
    final s = await _fresh({});
    addTearDown(s.dispose);
    s.servers = [_ours(), _foreign()];
    expect(s.hasAccess, isFalse,
        reason: 'наши платные серверы без оплаты закрыты');
    // А вот ВОЗМОЖНОСТИ приложения открыты: у человека есть рабочий сервер
    // своей подписки, и запирать от него настройки туннеля бессмысленно.
    expect(s.featuresUnlocked, isTrue);

    // Активным должен стать сервер СВОЕЙ подписки, а не наш платный.
    expect(s.activeServer?.foreign, isTrue,
        reason: 'без оплаты лучшим не может быть наш платный сервер');
  });

  test('7. просроченная подписка не открывает наши серверы', () async {
    final s = await _fresh({
      'sub_active_cache': true,
      'sub_until_cache':
          DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
      'access_granted': true,
    });
    addTearDown(s.dispose);
    await s.bootstrap();
    s.servers = [_ours()];
    expect(s.hasAccess, isFalse);
  });

  test('8. сервер, признанный мёртвым, забывается через время', () async {
    final srv = _ours();
    expect(srv.unreachable, isFalse);
    srv.unreachable = true;
    expect(srv.unreachable, isTrue, reason: 'метка ставится');
    // Метка временная: сервер мог моргнуть, вечная метка выкинула бы его
    // из выбора навсегда.
    srv.deadAt = DateTime.now().subtract(const Duration(minutes: 6));
    expect(srv.unreachable, isFalse, reason: 'метка обязана протухать');
  });

  test('9. страна определяется у любого сервера, не только у наших', () async {
    final cases = <VpnServer, String>{
      _ours(): 'NL',
      VpnServer(
          protocol: VpnProtocol.vless,
          name: 'Poland 1',
          address: '1.2.3.4',
          port: 443,
          raw: 'vless://u@1.2.3.4:443#PL'): 'PL',
      VpnServer(
          protocol: VpnProtocol.vless,
          name: 'Warsaw node',
          address: '1.2.3.4',
          port: 443,
          raw: 'x'): 'PL',
      VpnServer(
          protocol: VpnProtocol.vless,
          name: '[DE] node',
          address: '1.2.3.4',
          port: 443,
          raw: 'x'): 'DE',
      VpnServer(
          protocol: VpnProtocol.vless,
          name: 'Франция 2',
          address: '1.2.3.4',
          port: 443,
          raw: 'x'): 'FR',
      VpnServer(
          protocol: VpnProtocol.vless,
          name: 'node',
          address: 'srv.se',
          port: 443,
          raw: 'x'): 'SE',
    };
    cases.forEach((srv, expected) {
      expect(srv.countryCode, expected,
          reason: '«${srv.name}» / ${srv.address} → ожидали $expected');
    });
  });

  test('10. выбор метода замера не смешивается', () async {
    final s = await _fresh({});
    addTearDown(s.dispose);
    final a = _ours()..pingVia = 'tcp';
    s.servers = [a];
    s.pingType = 'proxy';
    // Смена метода обязана сбросить прошлые значения: иначе часть списка
    // показывает числа старого метода и кажется, что настройка не применилась.
    expect(a.pingMs, -1, reason: 'старое значение должно быть сброшено');
    expect(a.pingVia, isEmpty, reason: 'метод замера должен быть забыт');
  });
}
