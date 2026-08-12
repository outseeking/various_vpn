/// Правила маршрутизации без geo-списков.
///
/// Расследование показало: конфиг опирается на списки `geosite:` и `geoip:` —
/// обход РФ, блокировка рекламы, домены ИИ. На Android они лежат внутри ядра;
/// на других платформах их может не быть, а Xray при неизвестном списке не
/// пропускает правило, а ОТКАЗЫВАЕТСЯ СТАРТОВАТЬ — то есть VPN не включится
/// вовсе.
///
/// Здесь закреплено поведение чистки. Особенно важен второй тест: правило без
/// условий в Xray означает «подходит всё», и рекламное правило, оставшееся
/// пустым, заблокировало бы весь трафик человека.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/xray_config.dart';

Map<String, dynamic> _cfg(List<Map<String, dynamic>> rules) => {
      'outbounds': [
        {'tag': 'proxy', 'protocol': 'vless'},
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules},
    };

List<dynamic> _rulesOf(Map<String, dynamic> cfg) =>
    (cfg['routing'] as Map)['rules'] as List;

void main() {
  test('ссылки на списки вычищаются, явные домены остаются', () {
    final cfg = _cfg([
      {
        'type': 'field',
        'outboundTag': 'direct',
        'domain': ['geosite:category-ru', 'domain:sberbank.ru'],
      },
    ]);
    stripGeoRules(cfg);

    final rule = _rulesOf(cfg).single as Map;
    expect(rule['domain'], ['domain:sberbank.ru'],
        reason: 'явный домен обязан пережить чистку');
    expect(jsonEncode(cfg).contains('geosite:'), isFalse);
  });

  test('правило, оставшееся без условий, выбрасывается целиком', () {
    // Самая опасная ситуация: у правила «реклама → в блок» единственным
    // условием был geosite-список. Пустое условие в Xray значит «подходит
    // всё» — такое правило заблокировало бы весь трафик.
    final cfg = _cfg([
      {
        'type': 'field',
        'outboundTag': 'block',
        'domain': ['geosite:category-ads-all'],
      },
    ]);
    stripGeoRules(cfg);

    expect(_rulesOf(cfg), isEmpty,
        reason: 'иначе блокировка рекламы превращается в блокировку всего');
  });

  test('правила без geo не трогаем', () {
    final cfg = _cfg([
      {
        'type': 'field',
        'outboundTag': 'block',
        'port': '443',
        'network': 'udp',
      },
    ]);
    stripGeoRules(cfg);
    expect(_rulesOf(cfg), hasLength(1));
  });

  test('geoip чистится так же, как geosite', () {
    final cfg = _cfg([
      {
        'type': 'field',
        'outboundTag': 'direct',
        'ip': ['geoip:ru', '10.0.0.0/8'],
      },
    ]);
    stripGeoRules(cfg);
    expect((_rulesOf(cfg).single as Map)['ip'], ['10.0.0.0/8']);
  });
}
