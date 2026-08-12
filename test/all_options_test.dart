/// Сквозная проверка КАЖДОГО тумблера приложения.
///
/// Смысл: убедиться, что настройка не просто «нарисована», а доезжает до
/// конфига ядра и меняет поведение туннеля. Каждый тест смотрит итоговый
/// конфиг — то самое, что уходит в Xray.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/xray_config.dart';

/// Минимальный конфиг сервера — то, что отдаёт ядро по share-ссылке.
String _base() => jsonEncode({
      // Ядро отдаёт inbound с ВЫКЛЮЧЕННЫМ распознаванием доменов — ровно так,
      // как это приходит из share-ссылки.
      'inbounds': [
        {
          'tag': 'socks',
          'protocol': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'sniffing': {'enabled': false, 'destOverride': null},
        },
      ],
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': '198.51.100.1',
                'port': 443,
                'users': [
                  {'id': 'u', 'encryption': 'none'}
                ],
              }
            ]
          },
          'streamSettings': {'network': 'tcp', 'security': 'reality'},
        },
      ],
    });

Map<String, dynamic> _apply(NetOptions o) =>
    jsonDecode(applyNetOptions(_base(), o)) as Map<String, dynamic>;

List _rules(Map<String, dynamic> cfg) =>
    ((cfg['routing'] as Map?)?['rules'] as List?) ?? const [];

List<String> _tags(Map<String, dynamic> cfg) => (cfg['outbounds'] as List)
    .map((o) => '${(o as Map)['tag'] ?? ''}')
    .toList();

/// Есть ли правило, отправляющее что-то содержащее [needle] в [tag].
bool _routes(Map<String, dynamic> cfg, String tag, String needle) {
  for (final r in _rules(cfg)) {
    if ((r as Map)['outboundTag'] != tag) continue;
    final blob = jsonEncode(r);
    if (blob.contains(needle)) return true;
  }
  return false;
}

void main() {
  group('обход РФ-сайтов', () {
    test('включён: .ru и российские адреса идут мимо туннеля', () {
      final cfg = _apply(const NetOptions(bypassRu: true, smartAi: false));
      expect(_tags(cfg), contains('direct'));
      expect(_routes(cfg, 'direct', '.ru'), isTrue);
      expect(_routes(cfg, 'direct', 'geoip:ru'), isTrue);
    });

    test('выключен: таких правил нет вовсе', () {
      final cfg = _apply(const NetOptions(bypassRu: false, smartAi: false));
      expect(_routes(cfg, 'direct', 'geoip:ru'), isFalse);
    });
  });

  group('умный доступ к нейросетям', () {
    test('включён: домены ИИ принудительно через туннель', () {
      final cfg = _apply(const NetOptions(smartAi: true));
      expect(_routes(cfg, 'proxy', 'openai.com'), isTrue);
    });

    test('работает даже вместе с обходом РФ — правило ИИ идёт раньше', () {
      // Иначе .ru-правило перехватило бы часть доменов, и обещание «ИИ всегда
      // через сервер, где он работает» не выполнялось бы.
      final cfg = _apply(const NetOptions(bypassRu: true, smartAi: true));
      final rules = _rules(cfg);
      final ai = rules.indexWhere(
          (r) => jsonEncode(r).contains('openai.com'));
      final ru = rules.indexWhere((r) => jsonEncode(r).contains('geoip:ru'));
      expect(ai, isNonNegative);
      expect(ru, isNonNegative);
      expect(ai, lessThan(ru), reason: 'правило ИИ должно проверяться первым');
    });

    test('выключен: правил для ИИ нет', () {
      final cfg = _apply(const NetOptions(smartAi: false));
      expect(_routes(cfg, 'proxy', 'openai.com'), isFalse);
    });
  });

  group('блокировка рекламы и трекеров', () {
    test('включена: рекламные домены уходят в никуда', () {
      final cfg = _apply(const NetOptions(adBlock: true, smartAi: false));
      expect(_tags(cfg), contains('blocked'));
      final blocked = _rules(cfg).where((r) =>
          (r as Map)['outboundTag'] == 'blocked' &&
          (r['domain'] as List?)?.isNotEmpty == true);
      expect(blocked, isNotEmpty);
    });

    test('выключена: доменных правил в blackhole нет', () {
      final cfg = _apply(const NetOptions(adBlock: false, smartAi: false));
      final blocked = _rules(cfg).where((r) =>
          (r as Map)['outboundTag'] == 'blocked' &&
          (r['domain'] as List?)?.isNotEmpty == true);
      expect(blocked, isEmpty);
    });
  });

  group('домашняя сеть напрямую', () {
    test('включена: локальные адреса мимо туннеля', () {
      final cfg = _apply(const NetOptions(lanDirect: true, smartAi: false));
      expect(_routes(cfg, 'direct', 'geoip:private'), isTrue);
    });

    test('выключена: правила нет — весь трафик в туннель', () {
      final cfg = _apply(const NetOptions(lanDirect: false, smartAi: false));
      expect(_routes(cfg, 'direct', 'geoip:private'), isFalse);
    });
  });

  group('ускорение загрузки (мультиплексирование)', () {
    test('включено: появляется на рабочем outbound', () {
      final cfg = _apply(const NetOptions(mux: true, smartAi: false));
      final proxy = (cfg['outbounds'] as List).first as Map;
      expect((proxy['mux'] as Map?)?['enabled'], isTrue);
    });

    test('выключено: mux не появляется', () {
      final cfg = _apply(const NetOptions(mux: false, smartAi: false));
      final proxy = (cfg['outbounds'] as List).first as Map;
      expect((proxy['mux'] as Map?)?['enabled'], isNot(true));
    });
  });

  group('фрагментирование', () {
    test('включено: появляется отдельный outbound с фрагментацией', () {
      final cfg = _apply(const NetOptions(fragment: true, smartAi: false));
      final frag = (cfg['outbounds'] as List).firstWhere(
          (o) => (o as Map)['tag'] == 'fragment',
          orElse: () => null);
      expect(frag, isNotNull, reason: 'без него настройка ничего не делает');
      expect(jsonEncode(frag), contains('fragment'));
    });

    test('выключено: такого outbound нет', () {
      final cfg = _apply(const NetOptions(fragment: false, smartAi: false));
      expect(_tags(cfg), isNot(contains('fragment')));
    });
  });

  group('DNS и версия сети', () {
    test('свой DNS попадает в конфиг', () {
      final cfg = _apply(const NetOptions(
          dns: ['1.1.1.1', '8.8.8.8'], smartAi: false));
      expect((cfg['dns'] as Map)['servers'], ['1.1.1.1', '8.8.8.8']);
    });

    test('только IPv4 работает БЕЗ своего DNS — настройка самодостаточна', () {
      // Раньше выбор версии применялся только вместе со своим DNS, и сам по
      // себе не делал ничего.
      final cfg = _apply(
          const NetOptions(ipStrategy: IpStrategy.ipv4, smartAi: false));
      expect((cfg['dns'] as Map)['queryStrategy'], 'UseIPv4');
    });

    test('только IPv4 применяется и к прямым соединениям', () {
      final cfg = _apply(const NetOptions(
          ipStrategy: IpStrategy.ipv4, bypassRu: true, smartAi: false));
      final direct = (cfg['outbounds'] as List)
          .firstWhere((o) => (o as Map)['protocol'] == 'freedom') as Map;
      expect((direct['settings'] as Map)['domainStrategy'], 'UseIPv4');
    });

    test('предпочитать IPv6 — своя стратегия, а не та же самая', () {
      final cfg = _apply(
          const NetOptions(ipStrategy: IpStrategy.ipv6, smartAi: false));
      expect((cfg['dns'] as Map)['queryStrategy'], 'UseIPv6');
    });

    test('авто: DNS-блок не навязывается', () {
      final cfg = _apply(const NetOptions(smartAi: false));
      expect(cfg['dns'], isNull);
    });
  });


  group('бесплатный режим — только Telegram', () {
    test('Telegram в туннель, всё остальное блокируется', () {
      final cfg = _apply(const NetOptions(telegramOnly: true));
      // Домены и подсети Telegram — через прокси.
      expect(_routes(cfg, 'proxy', 't.me') || _routes(cfg, 'proxy', 'telegram'),
          isTrue);
      // Последнее правило — «всё прочее в никуда»: иначе бесплатный режим
      // раздавал бы полный VPN.
      final last = _rules(cfg).last as Map;
      expect(last['outboundTag'], 'blocked');
      expect('${last['network']}', contains('tcp'));
    });

    test('DNS идёт через туннель — иначе домены не резолвятся', () {
      final cfg = _apply(const NetOptions(telegramOnly: true));
      expect(_routes(cfg, 'proxy', '53'), isTrue);
    });

    test('адреса проверки связи доступны — иначе не проверить туннель', () {
      final cfg = _apply(const NetOptions(telegramOnly: true));
      expect(_routes(cfg, 'proxy', 'gstatic'), isTrue);
    });
  });

  group('всё вместе не конфликтует', () {
    test('полный набор настроек даёт валидный конфиг', () {
      final cfg = _apply(const NetOptions(
        dns: ['1.1.1.1'],
        bypassRu: true,
        ipStrategy: IpStrategy.ipv4,
        fragment: true,
        smartAi: true,
        adBlock: true,
        mux: true,
        lanDirect: true,
      ));
      final tags = _tags(cfg);
      expect(tags, contains('proxy'));
      expect(tags, contains('direct'));
      expect(tags, contains('blocked'));
      expect(tags, contains('fragment'));
      // Рабочий outbound обязан остаться первым: ядро берёт из него адрес.
      expect(tags.first, 'proxy');
      expect(_rules(cfg), isNotEmpty);
    });
  });

  group('распознавание доменов (sniffing)', () {
    // Без него доменные правила не срабатывают НИКОГДА: в режиме туннеля до
    // ядра доходит IP-адрес, а не имя сайта. Обход РФ, доступ к нейросетям и
    // блокировка рекламы держатся именно на доменах.
    test('включается принудительно', () {
      final cfg = _apply(const NetOptions(smartAi: true));
      final inb = (cfg['inbounds'] as List).first as Map;
      final sn = inb['sniffing'] as Map;
      expect(sn['enabled'], isTrue,
          reason: 'иначе доменная маршрутизация мертва');
    });

    test('распознаются HTTP, TLS и QUIC', () {
      final cfg = _apply(const NetOptions(smartAi: true));
      final sn = ((cfg['inbounds'] as List).first as Map)['sniffing'] as Map;
      expect(sn['destOverride'], containsAll(['http', 'tls', 'quic']));
    });

    test('адрес назначения подменяется распознанным доменом', () {
      // routeOnly=true оставил бы соединение на исходном IP — правила по
      // домену снова оказались бы ни при чём.
      final cfg = _apply(const NetOptions(smartAi: true));
      final sn = ((cfg['inbounds'] as List).first as Map)['sniffing'] as Map;
      expect(sn['routeOnly'], isFalse);
    });

    test('если сервис уже включил своё — не трогаем', () {
      final withOwn = jsonEncode({
        'inbounds': [
          {
            'protocol': 'socks',
            'port': 10808,
            'sniffing': {
              'enabled': true,
              'destOverride': ['tls'],
            },
          },
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'vless', 'settings': {}},
        ],
      });
      final cfg = jsonDecode(applyNetOptions(withOwn, const NetOptions()))
          as Map<String, dynamic>;
      final sn = ((cfg['inbounds'] as List).first as Map)['sniffing'] as Map;
      expect(sn['destOverride'], ['tls'], reason: 'выбор сервиса уважаем');
    });
  });

  group('готовые списки geosite', () {
    // geosite.dat лежит прямо в сборке (8 МБ) и ядро его видит. Раньше он не
    // использовался вовсе: рекламу резали по двум десяткам доменов, набранных
    // руками, хотя рядом лежал список на десятки тысяч записей.
    test('блокировка рекламы опирается на category-ads-all', () {
      final cfg = _apply(const NetOptions(adBlock: true, smartAi: false));
      expect(_routes(cfg, 'blocked', 'geosite:category-ads-all'), isTrue);
    });

    test('ручной список тоже остаётся — в нём русские сети', () {
      final cfg = _apply(const NetOptions(adBlock: true, smartAi: false));
      expect(_routes(cfg, 'blocked', 'mc.yandex.ru'), isTrue);
    });

    test('доступ к нейросетям использует список openai', () {
      final cfg = _apply(const NetOptions(smartAi: true));
      expect(_routes(cfg, 'proxy', 'geosite:openai'), isTrue);
    });

    test('список из панели полностью заменяет встроенный', () {
      // Иначе владелец не смог бы отключить geosite, если тот мешает.
      final cfg = _apply(const NetOptions(
          adBlock: true, smartAi: false, adDomains: ['ads.example']));
      expect(_routes(cfg, 'blocked', 'ads.example'), isTrue);
      expect(_routes(cfg, 'blocked', 'geosite:category-ads-all'), isFalse);
    });
  });
}
