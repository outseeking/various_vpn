/// Подписка приходит в четырёх разных форматах, и каждый из них когда-то
/// ломался. Фикстуры повторяют структуру живых панелей (значения выдуманы —
/// настоящих ключей в репозитории быть не должно).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';
import 'package:various_vpn/services/subscription_parser.dart';

/// Формат v2rayN: массив ПОЛНЫХ конфигов Xray, по конфигу на сервер.
/// Именно на нём подписка молча превращалась в «серверов нет».
const _xrayJsonArray = '''
[
  {
    "remarks": "🇩🇪 Германия | TCP",
    "outbounds": [
      {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {"vnext": [{
          "address": "198.51.100.10", "port": 443,
          "users": [{"id": "11111111-1111-4111-8111-111111111111",
                     "encryption": "none", "flow": "xtls-rprx-vision"}]
        }]},
        "streamSettings": {
          "network": "tcp", "security": "reality",
          "realitySettings": {"serverName": "de.example.com",
            "publicKey": "PUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUBKEYPUB",
            "shortId": "20af13feb995ce8b", "fingerprint": "firefox"}
        }
      },
      {"protocol": "freedom", "tag": "direct"},
      {"protocol": "blackhole", "tag": "block"}
    ]
  },
  {
    "remarks": "🇸🇪 Швеция | gRPC",
    "outbounds": [
      {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {"vnext": [{
          "address": "198.51.100.11", "port": 443,
          "users": [{"id": "22222222-2222-4222-8222-222222222222",
                     "encryption": "none"}]
        }]},
        "streamSettings": {
          "network": "grpc", "security": "tls",
          "grpcSettings": {"serviceName": "grpcline"},
          "tlsSettings": {"serverName": "se.example.com", "fingerprint": "chrome"}
        }
      },
      {"protocol": "freedom", "tag": "direct"}
    ]
  },
  {
    "remarks": "🇪🇪 Эстония | Trojan",
    "outbounds": [
      {
        "tag": "proxy",
        "protocol": "trojan",
        "settings": {"servers": [{
          "address": "198.51.100.12", "port": 8443, "password": "s3cret"
        }]},
        "streamSettings": {
          "network": "tcp", "security": "tls",
          "tlsSettings": {"serverName": "ee.example.com"}
        }
      }
    ]
  }
]
''';

/// sing-box: все узлы разом в одном конфиге, поля называются иначе.
const _singbox = '''
{
  "outbounds": [
    {
      "type": "vless", "tag": "Нидерланды",
      "server": "198.51.100.20", "server_port": 443,
      "uuid": "33333333-3333-4333-8333-333333333333",
      "flow": "xtls-rprx-vision",
      "tls": {"enabled": true, "server_name": "nl.example.com",
              "utls": {"enabled": true, "fingerprint": "chrome"},
              "reality": {"enabled": true, "public_key": "PK123", "short_id": "ab"}}
    },
    {
      "type": "trojan", "tag": "Япония",
      "server": "198.51.100.21", "server_port": 443, "password": "pw",
      "tls": {"enabled": true, "server_name": "jp.example.com"},
      "transport": {"type": "ws", "path": "/ray", "headers": {"Host": "jp.example.com"}}
    },
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"},
    {"type": "selector", "tag": "select", "outbounds": ["Нидерланды"]}
  ]
}
''';

/// Clash.Meta: YAML с секцией proxies.
const _clash = '''
port: 7890
proxies:
  - name: "🇺🇸 США"
    type: vless
    server: 198.51.100.30
    port: 443
    uuid: 44444444-4444-4444-8444-444444444444
    tls: true
    servername: us.example.com
    client-fingerprint: chrome
    flow: xtls-rprx-vision
    reality-opts:
      public-key: PKUS
      short-id: cd12
  - {name: "Сингапур WS", type: vmess, server: 198.51.100.31, port: 8080, uuid: 55555555-5555-4555-8555-555555555555, alterId: 0, cipher: auto, network: ws, ws-opts: {path: /vm, headers: {Host: sg.example.com}}}
  - name: "Быстрый QUIC"
    type: hysteria2
    server: 198.51.100.32
    port: 443
    password: hy2pass
proxy-groups:
  - name: PROXY
    type: select
''';

void main() {
  group('JSON-массив конфигов Xray (v2rayN)', () {
    test('распознаётся формат и все три сервера', () {
      final r = SubscriptionParser.parseDetailed(_xrayJsonArray);
      expect(r.format, SubFormat.xrayJson);
      expect(r.servers, hasLength(3));
      expect(r.usable, hasLength(3));
    });

    test('служебные outbound direct/block не становятся серверами', () {
      final r = SubscriptionParser.parseDetailed(_xrayJsonArray);
      expect(r.servers.map((s) => s.address),
          ['198.51.100.10', '198.51.100.11', '198.51.100.12']);
    });

    test('Reality со всеми параметрами доезжает до ссылки', () {
      final s = SubscriptionParser.parseDetailed(_xrayJsonArray).servers.first;
      expect(s.protocol, VpnProtocol.vless);
      expect(s.port, 443);
      expect(s.params['security'], 'reality');
      expect(s.params['sni'], 'de.example.com');
      expect(s.params['pbk'], startsWith('PUBKEY'));
      expect(s.params['sid'], '20af13feb995ce8b');
      expect(s.params['fp'], 'firefox');
      expect(s.params['flow'], 'xtls-rprx-vision');
      expect(s.params['type'], 'tcp');
    });

    test('gRPC сохраняет serviceName', () {
      final s = SubscriptionParser.parseDetailed(_xrayJsonArray).servers[1];
      expect(s.params['type'], 'grpc');
      expect(s.params['serviceName'], 'grpcline');
      expect(s.transportLabel, 'VLESS · TLS · gRPC');
    });

    test('trojan берёт пароль и порт из settings.servers', () {
      final s = SubscriptionParser.parseDetailed(_xrayJsonArray).servers[2];
      expect(s.protocol, VpnProtocol.trojan);
      expect(s.port, 8443);
      expect(s.raw, startsWith('trojan://s3cret@198.51.100.12:8443'));
    });

    test('ремарка с флагом даёт страну', () {
      final r = SubscriptionParser.parseDetailed(_xrayJsonArray);
      expect(r.servers[0].countryCode, 'DE');
      expect(r.servers[1].countryCode, 'SE');
      expect(r.servers[2].countryCode, 'EE');
    });
  });

  group('sing-box', () {
    test('берёт все узлы из одного конфига, служебные пропускает', () {
      final r = SubscriptionParser.parseDetailed(_singbox);
      expect(r.format, SubFormat.singbox);
      expect(r.servers, hasLength(2));
      expect(r.servers.map((s) => s.protocol),
          [VpnProtocol.vless, VpnProtocol.trojan]);
    });

    test('reality из вложенного tls-блока', () {
      final s = SubscriptionParser.parseDetailed(_singbox).servers.first;
      expect(s.params['security'], 'reality');
      expect(s.params['pbk'], 'PK123');
      expect(s.params['sid'], 'ab');
      expect(s.params['fp'], 'chrome');
      expect(s.params['flow'], 'xtls-rprx-vision');
    });

    test('websocket-транспорт переносится с путём и Host', () {
      final s = SubscriptionParser.parseDetailed(_singbox).servers[1];
      expect(s.params['type'], 'ws');
      expect(s.params['path'], '/ray');
      expect(s.params['host'], 'jp.example.com');
      expect(s.transportLabel, 'Trojan · TLS · WS');
    });
  });

  group('Clash YAML', () {
    test('разбирает и блочный, и однострочный синтаксис', () {
      final r = SubscriptionParser.parseDetailed(_clash);
      expect(r.format, SubFormat.clash);
      expect(r.servers, hasLength(3));
    });

    test('vless c reality-opts', () {
      final s = SubscriptionParser.parseDetailed(_clash).servers.first;
      expect(s.protocol, VpnProtocol.vless);
      expect(s.params['security'], 'reality');
      expect(s.params['pbk'], 'PKUS');
      expect(s.params['flow'], 'xtls-rprx-vision');
      expect(s.countryCode, 'US');
    });

    test('vmess собирается в base64-ссылку и читается обратно', () {
      final s = SubscriptionParser.parseDetailed(_clash).servers[1];
      expect(s.protocol, VpnProtocol.vmess);
      expect(s.address, '198.51.100.31');
      expect(s.port, 8080);
      final json = jsonDecode(
              utf8.decode(base64.decode(s.raw.substring('vmess://'.length))))
          as Map<String, dynamic>;
      expect(json['net'], 'ws');
      expect(json['path'], '/vm');
      expect(json['host'], 'sg.example.com');
    });

    test('hysteria2 распознан и работает — ядро её умеет', () {
      final r = SubscriptionParser.parseDetailed(_clash);
      final hy = r.servers[2];
      expect(hy.protocol, VpnProtocol.hysteria2);
      expect(hy.xraySupported, isTrue);
      expect(hy.raw, startsWith('hysteria2://hy2pass@198.51.100.32:443'));
      expect(r.usable, hasLength(3));
      expect(r.unsupportedLabels, isEmpty);
    });
  });

  group('старые форматы не сломались', () {
    test('обычный список ссылок', () {
      const raw = 'vless://uuid@1.2.3.4:443?security=reality#Берлин\n'
          'trojan://pw@5.6.7.8:443#Париж';
      final r = SubscriptionParser.parseDetailed(raw);
      expect(r.format, SubFormat.links);
      expect(r.servers, hasLength(2));
    });

    test('base64 от списка ссылок', () {
      final raw = base64.encode(utf8.encode(
          'vless://uuid@1.2.3.4:443#Берлин\ntrojan://pw@5.6.7.8:443#Париж'));
      final r = SubscriptionParser.parseDetailed(raw);
      expect(r.format, SubFormat.links);
      expect(r.servers, hasLength(2));
    });

    test('base64 от JSON-конфига тоже разворачивается', () {
      final raw = base64.encode(utf8.encode(_xrayJsonArray));
      final r = SubscriptionParser.parseDetailed(raw);
      expect(r.format, SubFormat.xrayJson);
      expect(r.servers, hasLength(3));
    });
  });

  group('пароль в ссылке', () {
    // Ядро (flutter_v2ray) берёт userInfo из ссылки БЕЗ декодирования. Если
    // закодировать пароль целиком, на сервер уйдёт «%2B» вместо «+», и
    // авторизация молча провалится — со стороны это выглядит как мёртвый
    // сервер. Поэтому обычные символы обязаны остаться нетронутыми.
    String linkFor(String password) {
      final body = jsonEncode([
        {
          'remarks': 'X',
          'outbounds': [
            {
              'protocol': 'trojan',
              'settings': {
                'servers': [
                  {'address': '198.51.100.9', 'port': 443, 'password': password}
                ]
              },
              'streamSettings': {'network': 'tcp', 'security': 'tls'}
            }
          ]
        }
      ]);
      return SubscriptionParser.parseDetailed(body).servers.single.raw;
    }

    test('спецсимволы пароля не экранируются лишний раз', () {
      expect(linkFor(r'p+a=s/w!o&rd').replaceFirst('trojan://', ''),
          startsWith(r'p+a=s%2fw!o&rd@'));
    });

    test('обычный пароль остаётся дословно', () {
      expect(linkFor('Simple123').replaceFirst('trojan://', ''),
          startsWith('Simple123@'));
    });

    test('ломающие разбор символы всё же экранируются, ссылка читается', () {
      final link = linkFor('pa@ss word');
      final s = SubscriptionParser.parseLink(link);
      expect(s, isNotNull, reason: 'ссылка обязана остаться разбираемой');
      expect(s!.address, '198.51.100.9');
    });
  });

  group('нераспознанное', () {
    test('HTML-страница не даёт фантомных серверов', () {
      const html = '<html><body>Подписка не найдена</body></html>';
      final r = SubscriptionParser.parseDetailed(html);
      expect(r.format, SubFormat.unknown);
      expect(r.servers, isEmpty);
    });

    test('обычная https-ссылка НЕ считается сервером', () {
      final r = SubscriptionParser.parseDetailed(
          'https://example.com/sub\nhttps://example.com/help');
      expect(r.servers, isEmpty);
      expect(r.format, SubFormat.unknown);
    });

    test('пустой JSON-массив', () {
      final r = SubscriptionParser.parseDetailed('[]');
      expect(r.servers, isEmpty);
    });

    test('дубликаты одного узла схлопываются', () {
      const raw = 'vless://uuid@1.2.3.4:443#A\nvless://uuid@1.2.3.4:443#A';
      expect(SubscriptionParser.parseDetailed(raw).servers, hasLength(1));
    });
  });
}
