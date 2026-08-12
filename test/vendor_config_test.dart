/// Подписки, которые отдают ГОТОВЫЕ конфиги, а не ссылки.
///
/// Такой конфиг несёт не только адрес сервера: там своя маршрутизация, DNS,
/// иногда балансировщики. Если пересобрать его по ссылке, всё это теряется и
/// сервис работает не так, как задумал владелец. Проверяем, что оригинал
/// сохраняется и доезжает до ядра целиком.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/subscription_parser.dart';
import 'package:various_vpn/services/xray_config.dart';

/// Урезанная копия реальной подписки: конфиг с DNS, маршрутизацией и
/// служебными outbound'ами — ровно как отдают панели формата v2rayN.
const _vendorSub = '''
[
  {
    "remarks": "🇩🇪 Германия",
    "dns": {"servers": ["1.1.1.1", "1.0.0.1"], "queryStrategy": "UseIP"},
    "log": {"loglevel": "warning"},
    "routing": {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {"type": "field", "protocol": ["bittorrent"], "outboundTag": "direct"},
        {"type": "field", "domain": ["full:tracker.example"], "outboundTag": "block"}
      ]
    },
    "inbounds": [
      {"tag": "socks", "port": 10808, "listen": "127.0.0.1",
       "protocol": "socks", "settings": {"udp": true}}
    ],
    "outbounds": [
      {"tag": "proxy", "protocol": "vless",
       "settings": {"vnext": [{"address": "198.51.100.70", "port": 443,
         "users": [{"id": "aaaa-bbbb", "encryption": "none",
                    "flow": "xtls-rprx-vision"}]}]},
       "streamSettings": {"network": "tcp", "security": "reality",
         "realitySettings": {"serverName": "de.example.com", "publicKey": "PK",
                             "shortId": "ab", "fingerprint": "chrome"}}},
      {"protocol": "freedom", "tag": "direct"},
      {"protocol": "blackhole", "tag": "block"}
    ]
  }
]
''';

void main() {
  group('готовый конфиг сохраняется', () {
    test('сервер несёт с собой исходный конфиг', () {
      final s = SubscriptionParser.parseDetailed(_vendorSub).usable.single;
      expect(s.fullConfig, isNotNull);
      final cfg = jsonDecode(s.fullConfig!) as Map<String, dynamic>;
      expect(cfg['routing'], isNotNull);
      expect(cfg['dns'], isNotNull);
      expect((cfg['routing'] as Map)['rules'], hasLength(2));
    });

    test('ссылка тоже собрана — она нужна для пинга и определения страны', () {
      final s = SubscriptionParser.parseDetailed(_vendorSub).usable.single;
      expect(s.raw, startsWith('vless://aaaa-bbbb@198.51.100.70:443'));
      expect(s.countryCode, 'DE');
    });

    test('подписка-СПИСОК ссылок конфига не несёт — его там и нет', () {
      final s = SubscriptionParser.parseDetailed(
              'vless://u@198.51.100.71:443?security=reality#Осло')
          .usable
          .single;
      expect(s.fullConfig, isNull);
    });
  });

  group('наши настройки не ломают чужую маршрутизацию', () {
    Map<String, dynamic> applied(NetOptions o) {
      final s = SubscriptionParser.parseDetailed(_vendorSub).usable.single;
      return jsonDecode(applyNetOptions(s.fullConfig!, o))
          as Map<String, dynamic>;
    }

    test('чужие правила остаются на месте', () {
      final cfg = applied(const NetOptions(bypassRu: true, adBlock: true));
      final rules = (cfg['routing'] as Map)['rules'] as List;
      final bt = rules.any((r) =>
          (r as Map)['protocol'] is List &&
          (r['protocol'] as List).contains('bittorrent'));
      expect(bt, isTrue, reason: 'правило сервиса про торренты пропало');
    });

    test('наши правила добавляются рядом, а не вместо', () {
      final cfg = applied(const NetOptions(bypassRu: true, smartAi: false));
      final rules = (cfg['routing'] as Map)['rules'] as List;
      expect(rules.length, greaterThan(2));
    });

    test('DNS сервиса не затирается, если свой не задан', () {
      final cfg = applied(const NetOptions(smartAi: false));
      expect((cfg['dns'] as Map)['servers'], contains('1.1.1.1'));
    });

    test('служебные outbound сервиса сохраняются', () {
      final cfg = applied(const NetOptions(smartAi: false));
      final tags = (cfg['outbounds'] as List)
          .map((o) => (o as Map)['tag'])
          .whereType<String>()
          .toList();
      expect(tags, contains('direct'));
      expect(tags.first, 'proxy', reason: 'ядро берёт адрес из первого');
    });
  });
}
