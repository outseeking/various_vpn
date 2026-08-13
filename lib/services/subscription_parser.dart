/// Парсер подписок и share-ссылок в список [VpnServer].
///
/// Единого стандарта подписок не существует, и панели отдают что угодно:
///  * список ссылок (`vless://…`), как есть или целиком в base64 — классика;
///  * JSON-массив готовых конфигов Xray (формат v2rayN) или один конфиг;
///  * конфиг sing-box с секцией `outbounds`;
///  * YAML Clash / Clash.Meta с секцией `proxies`.
///
/// Раньше понимался только первый вариант, и подписка в любом другом формате
/// выглядела для человека как «пустая». Теперь формат определяется по
/// содержимому, а конфиги приводятся обратно к ссылкам — дальше по приложению
/// сервер везде представлен именно ссылкой.
///
/// Здесь только чистая логика разбора (никакой сети) — модуль полностью
/// покрывается юнит-тестами.
library;

import 'dart:convert';

import '../models/vpn_server.dart';
import 'clash_yaml.dart';
import 'outbound_link.dart';

/// Формат, в котором пришла подписка. Нужен не для красоты: по нему
/// формулируется понятное сообщение, если серверов не нашлось.
enum SubFormat {
  links('список ссылок'),
  xrayJson('конфиг Xray'),
  singbox('конфиг sing-box'),
  clash('конфиг Clash'),
  unknown('неизвестный формат');

  const SubFormat(this.label);
  final String label;
}

/// Результат разбора: что распознали и в каком виде это пришло.
class SubParseResult {
  const SubParseResult(this.servers, this.format);

  /// Все распознанные серверы — включая те, что наше ядро не поднимает.
  final List<VpnServer> servers;
  final SubFormat format;

  /// Серверы, которые ядро реально умеет запускать.
  List<VpnServer> get usable => servers
      .where((s) => s.xraySupported && _routable(s))
      .toList(growable: false);

  /// Ведёт ли запись хоть куда-нибудь.
  ///
  /// Панели, которые не хотят обслуживать клиента, отвечают не ошибкой, а
  /// подпиской из одного конфига-заглушки: нулевой UUID, адрес 0.0.0.0, порт 1,
  /// в названии — «Приложение не поддерживается». Формально это валидный
  /// vless-адрес, и без этой проверки он попадал в список наравне с живыми
  /// серверами: человек видел сервер, которого не существует.
  static bool _routable(VpnServer s) {
    final a = s.address.trim();
    if (a.isEmpty || s.port <= 1 || s.port > 65535) return false;
    return a != '0.0.0.0' && a != '::' && a != '::0';
  }

  /// Названия протоколов, которые нашлись, но не поддерживаются, — чтобы
  /// сказать человеку конкретно, а не «ничего не подошло».
  List<String> get unsupportedLabels {
    final seen = <String>{};
    for (final s in servers) {
      if (!s.xraySupported) seen.add(s.protocol.label);
    }
    final list = seen.toList()..sort();
    return list;
  }
}

class SubscriptionParser {
  /// Хосты выведенных из эксплуатации нод — их конфиги отфильтровываем, чтобы
  /// клиент не видел заведомо нерабочий сервер (напр. сервер с истёкшей арендой).
  /// Серверный список подписки почистим отдельно; это защита на стороне клиента.
  static const deadHosts = <String>{
    '132.243.224.220', // DE2 / resale-host — аренда истекла
  };

  /// Разбирает сырое тело подписки в любом из поддерживаемых форматов.
  /// Мусорные/непонятные строки пропускаются молча.
  static List<VpnServer> parseContent(String content) =>
      parseDetailed(content).servers;

  /// То же, что [parseContent], но с информацией о формате и о протоколах,
  /// которые распознались, но не поддерживаются ядром.
  static SubParseResult parseDetailed(String content) {
    final text = _maybeBase64Decode(content.trim());
    final trimmed = text.trimLeft();

    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final fromJson = _parseJson(trimmed);
      if (fromJson != null) return fromJson;
    }
    if (ClashYaml.looksLikeClash(text)) {
      final servers = _clean(ClashYaml.parse(text));
      if (servers.isNotEmpty) return SubParseResult(servers, SubFormat.clash);
    }

    final servers = <VpnServer>[];
    for (final line in const LineSplitter().convert(text)) {
      // Обрамление снимаем ДО разбора. Ссылку часто копируют из JSON или из
      // сообщения, и она приезжает в кавычках, в угловых скобках или с
      // запятой на конце. Одного лишнего знака хватает, чтобы строка
      // перестала быть ссылкой, — а человек видит только «не добавляется».
      final s = line.trim().replaceAll(RegExp(r'''^["'<\s]+|["'>,;\s]+$'''), '');
      if (s.isEmpty) continue;
      final server = parseLink(s);
      if (server != null) servers.add(server);
    }
    return SubParseResult(
      _clean(servers),
      servers.isEmpty ? SubFormat.unknown : SubFormat.links,
    );
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
    final port = uri.hasPort ? uri.port : 443;
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

  /// Outbound'ы, которые сервером не являются: служебные каналы Xray и
  /// группы-переключатели sing-box. В конфиге они есть всегда.
  static const _notServers = {
    'freedom', 'blackhole', 'dns', 'loopback', // Xray
    'direct', 'block', 'selector', 'urltest', // sing-box
  };

  // ---- форматы-конфиги ----

  /// JSON: массив конфигов v2rayN, одиночный конфиг Xray, голый список
  /// outbound'ов или конфиг sing-box. Все четыре встречаются в живых панелях.
  static SubParseResult? _parseJson(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null; // не JSON — пусть попробуют другие разборщики
    }

    final servers = <VpnServer>[];
    var singbox = false;

    void takeOutbound(Object? raw, String remark, [Map? wholeConfig]) {
      if (raw is! Map) return;
      // sing-box описывает узел через `type`+`server`, Xray — через
      // `protocol`+`settings`. Различаем по наличию ключей, а не по догадке.
      final isSingbox = raw.containsKey('type') && raw.containsKey('server');
      final link = isSingbox
          ? singboxOutboundToLink(raw, remark: remark)
          : xrayOutboundToLink(raw, remark: remark);
      if (isSingbox) singbox = true;
      if (link == null) return;
      final s = parseLink(link);
      if (s == null) return;
      // Конфиг сохраняем целиком: в нём маршрутизация, DNS и балансировщики
      // сервиса. Ссылка их не переносит — ядру отдадим оригинал.
      if (wholeConfig != null && wholeConfig['outbounds'] is List) {
        s.fullConfig = jsonEncode(wholeConfig);
      }
      servers.add(s);
    }

    void takeConfig(Object? cfg) {
      if (cfg is! Map) return;
      final remark = '${cfg['remarks'] ?? cfg['remark'] ?? cfg['tag'] ?? ''}';
      final outbounds = cfg['outbounds'];
      if (outbounds is List) {
        // В конфиге всегда есть служебные direct/block. Берём только рабочий
        // outbound — обычно с тегом proxy, иначе первый неслужебный.
        final proxies = outbounds.where((o) {
          if (o is! Map) return false;
          final p = '${o['protocol'] ?? o['type'] ?? ''}'.toLowerCase();
          return p.isNotEmpty && !_notServers.contains(p);
        }).toList();
        if (proxies.isEmpty) return;
        // Один конфиг = один сервер (формат v2rayN). А вот sing-box держит
        // все узлы разом в одном списке — там берём каждый.
        final single = proxies.length == 1 || cfg.containsKey('remarks');
        for (final o in single ? [proxies.first] : proxies) {
          // Конфиг целиком передаём только когда он описывает ОДИН сервер:
          // иначе (sing-box со всеми узлами разом) непонятно, какой из них
          // включать, и отдавать такой конфиг ядру нельзя.
          takeOutbound(o, single ? remark : '${(o as Map)['tag'] ?? remark}',
              single ? cfg : null);
        }
        return;
      }
      // Голый outbound без обёртки.
      takeOutbound(cfg, remark);
    }

    // Отличаем «это конфиг, но пустой» от «это вообще не конфиг». Пустая
    // подписка — обычное дело (закончилась, ещё не выдана), и человеку про
    // неё надо сказать иначе, чем про битую ссылку.
    var recognized = false;
    if (decoded is List) {
      recognized = true;
      for (final item in decoded) {
        takeConfig(item);
      }
    } else if (decoded is Map) {
      recognized = decoded.containsKey('outbounds') ||
          decoded.containsKey('protocol') ||
          decoded.containsKey('type');
      takeConfig(decoded);
    }

    if (!recognized && servers.isEmpty) return null;
    return SubParseResult(
      _clean(servers),
      singbox ? SubFormat.singbox : SubFormat.xrayJson,
    );
  }

  // ---- внутреннее ----

  /// Выкидывает мёртвые ноды и дубликаты (один и тот же узел нередко приходит
  /// и в списке, и в конфиге).
  static List<VpnServer> _clean(List<VpnServer> servers) {
    final seen = <String>{};
    return servers
        .where((s) => !deadHosts.contains(s.address) && seen.add(s.raw))
        .toList();
  }

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
  /// Иначе возвращаем как есть (plain-text список ссылок или конфиг).
  static String _maybeBase64Decode(String input) {
    // Подписка обычно НЕ содержит '://' до декодирования. Если содержит —
    // это уже plain-text. Конфиги начинаются с { или [ — их тоже не трогаем.
    if (input.contains('://')) return input;
    if (input.startsWith('{') || input.startsWith('[')) return input;
    try {
      final decoded = _b64Decode(input);
      // Проверяем, что результат осмысленный: ссылки или конфиг.
      final head = decoded.trimLeft();
      if (decoded.contains('://') ||
          head.startsWith('{') ||
          head.startsWith('[')) {
        return decoded;
      }
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
