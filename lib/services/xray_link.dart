/// Построение полного Xray-JSON-конфига из share-ссылки (vless/vmess/trojan/ss)
/// ЧИСТО на Dart — без нативного парсера.
///
/// Зачем: на Android JSON собирает `flutter_v2ray` (FlutterV2ray.parseFromURL);
/// на iOS этого плагина нет, поэтому конфиг для нативного ядра (libXray в
/// NetworkExtension) собираем здесь. Формат идентичен тому, что отдаёт Android,
/// поэтому поверх него работает тот же [applyNetOptions] — а значит на iOS
/// СОХРАНЯЮТСЯ все функции роутинга: обход РФ, умный доступ к ИИ, AdBlock,
/// фрагментация, бесплатный режим «только Telegram».
///
/// Файл чисто платформонезависимый (нет dart:io / плагинов), поэтому безопасно
/// компилируется и на Android (там просто не используется).
library;

import 'dart:convert';

/// Локальные порты SOCKS/HTTP-инбаундов туннеля (их слушает tun2socks на iOS).
const int kXraySocksPort = 10808;
const int kXrayHttpPort = 10809;

/// Собирает полный Xray-конфиг (inbounds + outbound) из [rawUrl].
/// Бросает [FormatException], если ссылку не удалось разобрать.
Map<String, dynamic> buildXrayConfig(String rawUrl) {
  final scheme = rawUrl.split('://').first.toLowerCase();
  final Map<String, dynamic> outbound = switch (scheme) {
    'vless' => _vless(rawUrl),
    'vmess' => _vmess(rawUrl),
    'trojan' => _trojan(rawUrl),
    'ss' || 'shadowsocks' => _shadowsocks(rawUrl),
    _ => throw FormatException('Неподдерживаемая схема: $scheme'),
  };
  outbound['tag'] = 'proxy';
  return {
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {
        'tag': 'socks',
        'port': kXraySocksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'udp': true, 'auth': 'noauth'},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': false,
        },
      },
      {
        'tag': 'http',
        'port': kXrayHttpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': {},
      },
    ],
    'outbounds': [
      outbound,
      {'protocol': 'freedom', 'tag': 'direct'},
      {'protocol': 'blackhole', 'tag': 'block'},
    ],
    'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': []},
  };
}

/// Полный конфиг в виде JSON-строки (как getFullConfiguration на Android).
String buildXrayConfigJson(String rawUrl) => jsonEncode(buildXrayConfig(rawUrl));

// ---------- VLESS ----------
Map<String, dynamic> _vless(String url) {
  final u = Uri.parse(url);
  final id = Uri.decodeComponent(u.userInfo);
  final p = u.queryParameters;
  final user = <String, dynamic>{
    'id': id,
    'encryption': p['encryption'] ?? 'none',
  };
  if ((p['flow'] ?? '').isNotEmpty) user['flow'] = p['flow'];
  return {
    'protocol': 'vless',
    'settings': {
      'vnext': [
        {
          'address': u.host,
          'port': u.port == 0 ? 443 : u.port,
          'users': [user],
        }
      ]
    },
    'streamSettings': _stream(u.host, p),
    'mux': {'enabled': false},
  };
}

// ---------- Trojan ----------
Map<String, dynamic> _trojan(String url) {
  final u = Uri.parse(url);
  final pass = Uri.decodeComponent(u.userInfo);
  final p = u.queryParameters;
  return {
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {
          'address': u.host,
          'port': u.port == 0 ? 443 : u.port,
          'password': pass,
        }
      ]
    },
    'streamSettings': _stream(u.host, p),
    'mux': {'enabled': false},
  };
}

// ---------- VMess (vmess://base64(json)) ----------
Map<String, dynamic> _vmess(String url) {
  final b64 = url.substring('vmess://'.length).trim();
  final jsonStr = utf8.decode(base64.decode(_pad(b64)));
  final v = jsonDecode(jsonStr) as Map<String, dynamic>;
  String s(String k) => (v[k] ?? '').toString();
  final net = s('net').isEmpty ? 'tcp' : s('net');
  final tls = s('tls');
  final host = s('add');
  final params = <String, String>{
    'type': net,
    'security': tls.isEmpty ? 'none' : tls,
    if (s('sni').isNotEmpty) 'sni': s('sni'),
    if (s('host').isNotEmpty) 'host': s('host'),
    if (s('path').isNotEmpty) 'path': s('path'),
    if (s('alpn').isNotEmpty) 'alpn': s('alpn'),
    if (net == 'grpc' && s('path').isNotEmpty) 'serviceName': s('path'),
  };
  return {
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': host,
          'port': int.tryParse(s('port')) ?? 443,
          'users': [
            {
              'id': s('id'),
              'alterId': int.tryParse(s('aid')) ?? 0,
              'security': s('scy').isEmpty ? 'auto' : s('scy'),
            }
          ],
        }
      ]
    },
    'streamSettings': _stream(host, params),
    'mux': {'enabled': false},
  };
}

// ---------- Shadowsocks ----------
Map<String, dynamic> _shadowsocks(String url) {
  var body = url.substring(url.indexOf('://') + 3);
  final hash = body.indexOf('#');
  if (hash >= 0) body = body.substring(0, hash);
  String method, pass, host;
  int port;
  if (body.contains('@')) {
    final at = body.lastIndexOf('@');
    var creds = body.substring(0, at);
    final hp = body.substring(at + 1);
    // creds может быть base64(method:pass)
    if (!creds.contains(':')) creds = utf8.decode(base64.decode(_pad(creds)));
    final ci = creds.indexOf(':');
    method = creds.substring(0, ci);
    pass = creds.substring(ci + 1);
    final colon = hp.lastIndexOf(':');
    host = hp.substring(0, colon);
    port = int.tryParse(hp.substring(colon + 1)) ?? 443;
  } else {
    final dec = utf8.decode(base64.decode(_pad(body)));
    final at = dec.lastIndexOf('@');
    final creds = dec.substring(0, at);
    final hp = dec.substring(at + 1);
    final ci = creds.indexOf(':');
    method = creds.substring(0, ci);
    pass = creds.substring(ci + 1);
    final colon = hp.lastIndexOf(':');
    host = hp.substring(0, colon);
    port = int.tryParse(hp.substring(colon + 1)) ?? 443;
  }
  return {
    'protocol': 'shadowsocks',
    'settings': {
      'servers': [
        {'address': host, 'port': port, 'method': method, 'password': pass}
      ]
    },
    'streamSettings': {'network': 'tcp'},
    'mux': {'enabled': false},
  };
}

// ---------- общий streamSettings по query-параметрам ----------
Map<String, dynamic> _stream(String host, Map<String, String> p) {
  final net = (p['type'] ?? 'tcp').toLowerCase();
  final sec = (p['security'] ?? 'none').toLowerCase();
  final sni = p['sni'] ?? p['peer'] ?? host;
  final fp = p['fp'] ?? 'chrome';
  final ss = <String, dynamic>{'network': net == 'h2' ? 'http' : net};

  if (sec == 'reality') {
    ss['security'] = 'reality';
    ss['realitySettings'] = {
      'serverName': sni,
      'fingerprint': fp,
      'publicKey': p['pbk'] ?? '',
      'shortId': p['sid'] ?? '',
      'spiderX': p['spx'] ?? '',
      if ((p['flow'] ?? '').isNotEmpty) 'show': false,
    };
  } else if (sec == 'tls') {
    ss['security'] = 'tls';
    ss['tlsSettings'] = {
      'serverName': sni,
      'fingerprint': fp,
      'allowInsecure': (p['allowInsecure'] ?? '0') == '1',
      if ((p['alpn'] ?? '').isNotEmpty)
        'alpn': p['alpn']!.split(',').map((e) => e.trim()).toList(),
    };
  } else {
    ss['security'] = 'none';
  }

  switch (net) {
    case 'grpc':
      ss['grpcSettings'] = {
        'serviceName': p['serviceName'] ?? p['path'] ?? '',
        'multiMode': (p['mode'] ?? '') == 'multi',
      };
      break;
    case 'ws':
      ss['wsSettings'] = {
        'path': p['path'] ?? '/',
        'headers': {'Host': p['host'] ?? sni},
      };
      break;
    case 'httpupgrade':
      ss['httpupgradeSettings'] = {
        'path': p['path'] ?? '/',
        'host': p['host'] ?? sni,
      };
      break;
    case 'http':
    case 'h2':
      ss['httpSettings'] = {
        'path': p['path'] ?? '/',
        'host': [p['host'] ?? sni],
      };
      break;
    case 'tcp':
    default:
      if ((p['headerType'] ?? 'none') == 'http') {
        ss['tcpSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'path': [p['path'] ?? '/'],
              'headers': {
                'Host': [p['host'] ?? sni]
              }
            }
          }
        };
      }
      break;
  }
  return ss;
}

String _pad(String b64) {
  var s = b64.replaceAll('-', '+').replaceAll('_', '/');
  final m = s.length % 4;
  if (m != 0) s += '=' * (4 - m);
  return s;
}
