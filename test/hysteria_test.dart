/// Hysteria: разбор ссылок, признание протокола рабочим и безопасность
/// конфига.
///
/// Поддержка появилась не отдельным движком, а переходом на свежую сборку
/// Xray — в ней есть proxy/hysteria. Поэтому проверяем ровно то, что могло
/// сломаться при таком переходе: что ссылка разбирается, что сервер больше не
/// считается неподдерживаемым и что сборщик конфига не навешивает на него mux.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/subscription_parser.dart';
import 'package:various_vpn/services/xray_config.dart';

void main() {
  group('ссылки', () {
    test('hysteria2:// разбирается как рабочий сервер', () {
      final s = SubscriptionParser.parseLink(
          'hysteria2://p4ssw0rd@198.51.100.40:443?sni=de.example.com#Германия');
      expect(s, isNotNull);
      expect(s!.protocol, VpnProtocol.hysteria2);
      expect(s.address, '198.51.100.40');
      expect(s.port, 443);
      expect(s.xraySupported, isTrue,
          reason: 'после смены ядра Hysteria должна стать рабочей');
      expect(s.countryCode, 'DE');
      expect(s.transportLabel, 'Hysteria2 · QUIC');
    });

    test('короткая форма hy2:// — тот же протокол', () {
      final s = SubscriptionParser.parseLink('hy2://pw@198.51.100.41:8443#X');
      expect(s!.protocol, VpnProtocol.hysteria2);
      expect(s.xraySupported, isTrue);
    });

    test('первая версия отличается от второй, а не сливается с ней', () {
      final v1 = SubscriptionParser.parseLink('hysteria://pw@198.51.100.42:443#A');
      final v2 = SubscriptionParser.parseLink('hysteria2://pw@198.51.100.42:443#A');
      expect(v1!.protocol, VpnProtocol.hysteria);
      expect(v2!.protocol, VpnProtocol.hysteria2);
      expect(v1.protocol.label, 'Hysteria');
      expect(v2.protocol.label, 'Hysteria2');
    });

    test('TUIC и WireGuard по-прежнему честно помечены неподдерживаемыми', () {
      // Xray их не умеет, и делать вид, что умеет, нельзя: человек выбрал бы
      // такой сервер и получил молчаливый отказ подключения.
      final tuic = SubscriptionParser.parseLink('tuic://u:p@198.51.100.43:443#T');
      final wg = SubscriptionParser.parseLink('wg://k@198.51.100.44:51820#W');
      expect(tuic!.xraySupported, isFalse);
      expect(wg!.xraySupported, isFalse);
    });
  });

  group('подписка с Hysteria', () {
    test('смешанный список: сервер на Hysteria больше не отсеивается', () {
      const raw = 'vless://u@198.51.100.50:443?security=reality#Осло\n'
          'hysteria2://pw@198.51.100.51:443#Токио\n'
          'tuic://u:p@198.51.100.52:443#Лишний';
      final r = SubscriptionParser.parseDetailed(raw);
      expect(r.servers, hasLength(3));
      expect(r.usable, hasLength(2));
      expect(r.usable.map((s) => s.protocol),
          containsAll([VpnProtocol.vless, VpnProtocol.hysteria2]));
      expect(r.unsupportedLabels, ['TUIC']);
    });

    test('Clash-подписка с hysteria2 отдаёт рабочий сервер', () {
      const yaml = '''
proxies:
  - name: "Быстрый"
    type: hysteria2
    server: 198.51.100.53
    port: 443
    password: hy2pass
    sni: fast.example.com
''';
      final r = SubscriptionParser.parseDetailed(yaml);
      expect(r.usable, hasLength(1));
      final s = r.usable.single;
      expect(s.protocol, VpnProtocol.hysteria2);
      expect(s.params['sni'], 'fast.example.com');
      expect(s.raw, startsWith('hysteria2://hy2pass@198.51.100.53:443'));
    });
  });

  group('сборка конфига', () {
    /// Такой outbound строит ядро для hysteria2-ссылки.
    String hysteriaConfig() => jsonEncode({
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'hysteria',
              'settings': {
                'address': '198.51.100.60',
                'port': 443,
                'version': 2,
              },
              'streamSettings': {
                'network': 'hysteria',
                'security': 'tls',
                'tlsSettings': {'serverName': 'h.example.com'},
                'hysteriaSettings': {'version': 2, 'auth': 'pw'},
              },
            },
          ],
        });

    Map first(String out) =>
        (jsonDecode(out)['outbounds'] as List).first as Map;

    test('mux НЕ навешивается на Hysteria', () {
      // QUIC мультиплексирует потоки сам. Второй слой поверх — лишние
      // заголовки и потерянная скорость там, где скорость и есть смысл.
      final out =
          applyNetOptions(hysteriaConfig(), const NetOptions(mux: true));
      expect((first(out)['mux'] as Map?)?['enabled'], isNot(true));
    });

    test('настройки hysteria переживают сборку конфига без потерь', () {
      final out = applyNetOptions(
          hysteriaConfig(), const NetOptions(bypassRu: true, adBlock: true));
      final o = first(out);
      final ss = o['streamSettings'] as Map;
      expect(o['protocol'], 'hysteria');
      expect(ss['network'], 'hysteria');
      expect((ss['hysteriaSettings'] as Map)['auth'], 'pw');
      expect((ss['hysteriaSettings'] as Map)['version'], 2);
      expect((ss['tlsSettings'] as Map)['serverName'], 'h.example.com');
    });

    test('маршрутизация вокруг Hysteria работает как обычно', () {
      final out = applyNetOptions(
          hysteriaConfig(), const NetOptions(bypassRu: true, smartAi: false));
      final cfg = jsonDecode(out) as Map<String, dynamic>;
      final tags =
          (cfg['outbounds'] as List).map((o) => (o as Map)['tag']).toList();
      expect(tags, contains('proxy'));
      expect(tags, contains('direct'));
    });
  });
}
