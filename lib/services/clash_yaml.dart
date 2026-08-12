/// Разбор подписок в формате Clash / Clash.Meta.
///
/// Clash описывает узлы YAML-секцией `proxies:` со своими именами полей
/// (`servername` вместо sni, `ws-opts.path` вместо path и т.д.). Приводим их к
/// share-ссылке — дальше сервер ничем не отличается от обычного импорта.
///
/// Чистая логика без сети и без Flutter — покрывается юнит-тестами.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../models/vpn_server.dart';
import 'outbound_link.dart';
import 'subscription_parser.dart';

class ClashYaml {
  /// Дёшево проверяет, похоже ли тело на Clash-конфиг: секция `proxies:` в
  /// начале строки. Полный разбор YAML ради этой проверки не нужен.
  static bool looksLikeClash(String text) =>
      RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(text);

  /// Разбирает секцию `proxies:`. Узлы, которые не удалось понять,
  /// пропускаются молча — из-за одного кривого не должна теряться подписка.
  static List<VpnServer> parse(String text) {
    Object? doc;
    try {
      doc = loadYaml(text);
    } catch (_) {
      return const [];
    }
    if (doc is! Map) return const [];
    final proxies = doc['proxies'];
    if (proxies is! List) return const [];

    final servers = <VpnServer>[];
    for (final p in proxies) {
      if (p is! Map) continue;
      final link = _toLink(p);
      if (link == null) continue;
      final s = SubscriptionParser.parseLink(link);
      if (s != null) servers.add(s);
    }
    return servers;
  }

  // ---- внутреннее ----

  static String? _toLink(Map p) {
    final type = '${p['type'] ?? ''}'.toLowerCase();
    final host = '${p['server'] ?? ''}'.trim();
    if (host.isEmpty) return null;
    final port = _toInt(p['port']) ?? 443;
    final name = '${p['name'] ?? ''}';

    final q = _query(p, type);

    switch (type) {
      case 'vless':
        final id = '${p['uuid'] ?? ''}';
        if (id.isEmpty) return null;
        q['encryption'] = 'none';
        _put(q, 'flow', p['flow']);
        return _uri('vless', id, host, port, q, name);

      case 'trojan':
        final pass = '${p['password'] ?? ''}';
        if (pass.isEmpty) return null;
        // У Clash trojan TLS включён всегда, отдельного поля может не быть.
        q['security'] = 'tls';
        return _uri('trojan', pass, host, port, q, name);

      case 'vmess':
        final id = '${p['uuid'] ?? ''}';
        if (id.isEmpty) return null;
        final json = {
          'v': '2',
          'ps': name,
          'add': host,
          'port': '$port',
          'id': id,
          'aid': '${_toInt(p['alterId']) ?? 0}',
          'scy': '${p['cipher'] ?? 'auto'}',
          'net': q['type'] ?? 'tcp',
          'type': 'none',
          'host': q['host'] ?? '',
          'path': q['type'] == 'grpc' ? (q['serviceName'] ?? '') : (q['path'] ?? ''),
          'tls': q['security'] ?? '',
          'sni': q['sni'] ?? '',
          'alpn': q['alpn'] ?? '',
          'fp': q['fp'] ?? '',
        };
        return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';

      case 'ss':
      case 'shadowsocks':
        final cipher = '${p['cipher'] ?? ''}';
        final pass = '${p['password'] ?? ''}';
        if (cipher.isEmpty || pass.isEmpty) return null;
        final userinfo = base64Url.encode(utf8.encode('$cipher:$pass'));
        return 'ss://$userinfo@$host:$port${_fragment(name)}';

      // Собираем ссылку и для неподдерживаемых протоколов: пусть человек
      // увидит честную причину, а не молча потеряет половину подписки.
      case 'hysteria2':
      case 'hysteria':
        final pass = '${p['password'] ?? p['auth-str'] ?? p['auth_str'] ?? ''}';
        return _uri(type, pass, host, port, q, name);

      case 'tuic':
        final id = '${p['uuid'] ?? ''}';
        final pass = '${p['password'] ?? ''}';
        return _uri('tuic', '$id:$pass', host, port, q, name);

      case 'anytls':
        final pass = '${p['password'] ?? ''}';
        return _uri('anytls', pass, host, port, q, name);
    }
    return null;
  }

  static Map<String, String> _query(Map p, String type) {
    final q = <String, String>{};
    final network = '${p['network'] ?? 'tcp'}'.toLowerCase();
    q['type'] = network.isEmpty ? 'tcp' : network;

    final reality = _asMap(p['reality-opts']);
    if (reality.isNotEmpty) {
      q['security'] = 'reality';
      _put(q, 'pbk', reality['public-key']);
      _put(q, 'sid', reality['short-id']);
    } else if (p['tls'] == true || type == 'trojan') {
      q['security'] = 'tls';
    }
    _put(q, 'sni', p['servername'] ?? p['sni'] ?? p['peer']);
    _put(q, 'fp', p['client-fingerprint']);
    _put(q, 'alpn', _joinList(p['alpn']));
    if (p['skip-cert-verify'] == true) q['allowInsecure'] = '1';

    switch (network) {
      case 'ws':
        final ws = _asMap(p['ws-opts']);
        _put(q, 'path', ws['path']);
        _put(q, 'host', _asMap(ws['headers'])['Host'] ?? ws['host']);
        break;
      case 'grpc':
        _put(q, 'serviceName', _asMap(p['grpc-opts'])['grpc-service-name']);
        break;
      case 'h2':
        final h = _asMap(p['h2-opts']);
        _put(q, 'path', h['path']);
        _put(q, 'host', _joinList(h['host']));
        break;
      case 'http':
        final h = _asMap(p['http-opts']);
        _put(q, 'path', _joinList(h['path']));
        _put(q, 'host', _joinList(_asMap(h['headers'])['Host']));
        break;
    }
    return q;
  }

  static String _uri(String scheme, String userinfo, String host, int port,
      Map<String, String> q, String remark) {
    final cleaned = Map<String, String>.from(q)
      ..removeWhere((_, v) => v.isEmpty);
    final query = cleaned.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final h = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
    // Пароль экранируется по минимуму: ядро читает его из ссылки без
    // декодирования (см. encodeUserInfo).
    return '$scheme://${encodeUserInfo(userinfo)}@$h:$port'
        '${query.isEmpty ? '' : '?$query'}${_fragment(remark)}';
  }

  static String _fragment(String remark) =>
      remark.isEmpty ? '' : '#${Uri.encodeComponent(remark)}';

  static void _put(Map<String, String> q, String key, Object? value) {
    final s = '${value ?? ''}';
    if (s.isNotEmpty) q[key] = s;
  }

  static Map _asMap(Object? v) => v is Map ? v : const {};

  static int? _toInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  static String _joinList(Object? v) {
    if (v == null) return '';
    if (v is List) {
      return v.map((e) => '$e').where((e) => e.isNotEmpty).join(',');
    }
    return '$v';
  }
}
