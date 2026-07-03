// Юнит-тесты парсера подписки — чистая логика, гоняется без устройства:
//   flutter test
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/subscription_parser.dart';

void main() {
  group('parseLink', () {
    test('VLESS+Reality разбирается, raw сохраняется целиком', () {
      const link =
          'vless://11112222-3333-4444-5555-666677778888@de1.ug-connect.site:443'
          '?type=tcp&security=reality&pbk=ABC&fp=chrome&sni=vgtrk.ru&sid=00'
          '&spx=%2F#DE-1%20Germany';
      final s = SubscriptionParser.parseLink(link);
      expect(s, isNotNull);
      expect(s!.protocol, VpnProtocol.vless);
      expect(s.address, 'de1.ug-connect.site');
      expect(s.port, 443);
      expect(s.name, 'DE-1 Germany');
      expect(s.params['sni'], 'vgtrk.ru');
      expect(s.raw, link); // важно: ядру отдаём исходную ссылку
      expect(s.countryCode, 'DE');
    });

    test('Hysteria2 (hy2 алиас) разбирается', () {
      const link = 'hy2://secret@fi1.ug-connect.site:26682?insecure=0#Finland';
      final s = SubscriptionParser.parseLink(link);
      expect(s, isNotNull);
      expect(s!.protocol, VpnProtocol.hysteria2);
      expect(s.address, 'fi1.ug-connect.site');
      expect(s.countryCode, 'FI');
    });

    test('мусорные/мета-строки игнорируются', () {
      expect(SubscriptionParser.parseLink('ShadowTLS is Not Supported'), isNull);
      expect(SubscriptionParser.parseLink('https://x/sub/clash'), isNull);
      expect(SubscriptionParser.parseLink(''), isNull);
    });
  });

  group('parseContent', () {
    final links = [
      'vless://aaa@nl1.ug-connect.site:443?security=reality&sni=a#NL',
      'hysteria2://pw@de2.ug-connect.site:29268#DE-2',
    ].join('\n');

    test('plain-text список ссылок', () {
      final servers = SubscriptionParser.parseContent(links);
      expect(servers.length, 2);
      expect(servers[0].countryCode, 'NL');
      expect(servers[1].protocol, VpnProtocol.hysteria2);
    });

    test('base64-подписка декодируется', () {
      final b64 = base64.encode(utf8.encode(links));
      final servers = SubscriptionParser.parseContent(b64);
      expect(servers.length, 2);
    });

    test('base64 без паддинга (url-safe) тоже', () {
      var b64 = base64Url.encode(utf8.encode(links)).replaceAll('=', '');
      final servers = SubscriptionParser.parseContent(b64);
      expect(servers.length, 2);
    });
  });
}
