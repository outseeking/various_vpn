/// Парсер subscription-ссылок и share-ссылок в список [VpnServer].
///
/// Стандарт подписки v2ray/Hiddify: тело ответа — это base64 от списка ссылок,
/// разделённых переводами строки (иногда plain-text без base64). Каждая ссылка —
/// vless://, hysteria2://, trojan:// и т.п. Здесь только чистая логика разбора
/// (никакой сети) — поэтому модуль полностью тестируется в Web/юнит-тестами.
library;

import 'dart:convert';

import '../models/vpn_server.dart';

class SubscriptionParser {
  /// Разбирает сырое тело подписки (base64 ИЛИ plain-text) в список серверов.
  /// Мусорные/непонятные строки пропускаются молча.
  static List<VpnServer> parseContent(String content) {
    final text = _maybeBase64Decode(content.trim());
    final lines = const LineSplitter().convert(text);
    final servers = <VpnServer>[];
    for (final line in lines) {
      final s = line.trim();
      if (s.isEmpty) continue;
      final server = parseLink(s);
      if (server != null) servers.add(server);
    }
    return servers;
  }

  /// Разбирает одну share-ссылку. Возвращает null, если это не похоже на
  /// поддерживаемую ссылку (мета-ссылка подписки, текст и т.п.).
  static VpnServer? parseLink(String link) {
    final schemeEnd = link.indexOf('://');
    if (schemeEnd <= 0) return null;
    final scheme = link.substring(0, schemeEnd).toLowerCase();
    final protocol = VpnProtocol.fromScheme(scheme);
    if (protocol == VpnProtocol.unknown) return null;

    // vmess:// кодируется иначе (base64 JSON) — обработаем отдельно.
    if (protocol == VpnProtocol.vmess) {
      return _parseVmess(link);
    }

    // Общий формат: scheme://userinfo@host:port?query#fragment
    Uri? uri;
    try {
      uri = Uri.parse(link);
    } catch (_) {
      return null;
    }
    final host = uri.host;
    if (host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : _defaultPort(protocol);
    final name = uri.fragment.isNotEmpty
        ? Uri.decodeComponent(uri.fragment)
        : '$host:$port';

    return VpnServer(
      protocol: protocol,
      name: name,
      address: host,
      port: port,
      raw: link,
      params: uri.queryParameters,
    );
  }

  // ---- внутреннее ----

  static int _defaultPort(VpnProtocol p) => switch (p) {
        VpnProtocol.hysteria2 || VpnProtocol.tuic => 443,
        _ => 443,
      };

  /// vmess://BASE64(json{add,port,ps,...}).
  static VpnServer? _parseVmess(String link) {
    try {
      final b64 = link.substring('vmess://'.length);
      final json = jsonDecode(_b64Decode(b64)) as Map<String, dynamic>;
      final host = (json['add'] ?? '').toString();
      if (host.isEmpty) return null;
      final port = int.tryParse('${json['port']}') ?? 443;
      final name = (json['ps'] ?? '$host:$port').toString();
      return VpnServer(
        protocol: VpnProtocol.vmess,
        name: name,
        address: host,
        port: port,
        raw: link,
        params: json.map((k, v) => MapEntry(k, '$v')),
      );
    } catch (_) {
      return null;
    }
  }

  /// Если строка целиком — валидный base64 (типичная подписка), декодируем.
  /// Иначе возвращаем как есть (plain-text список ссылок).
  static String _maybeBase64Decode(String input) {
    // Подписка обычно НЕ содержит '://' до декодирования. Если содержит —
    // это уже plain-text список ссылок.
    if (input.contains('://')) return input;
    try {
      final decoded = _b64Decode(input);
      // Проверяем, что результат осмысленный (есть схема ссылки).
      if (decoded.contains('://')) return decoded;
    } catch (_) {
      // не base64 — оставляем как есть
    }
    return input;
  }

  /// Декод base64 с поддержкой url-safe и отсутствующего паддинга.
  static String _b64Decode(String s) {
    var t = s.replaceAll('\n', '').replaceAll('\r', '').trim();
    t = t.replaceAll('-', '+').replaceAll('_', '/');
    final pad = t.length % 4;
    if (pad > 0) t = t + '=' * (4 - pad);
    return utf8.decode(base64.decode(t));
  }
}
