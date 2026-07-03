/// Пост-обработка Xray-конфига перед запуском ядра.
///
/// flutter_v2ray отдаёт готовый JSON из vless://-ссылки, но без наших сетевых
/// настроек. Здесь мы дописываем в этот JSON:
///  - свой DNS (если задан пользователем);
///  - стратегию адресов IPv4/IPv6 (domainStrategy);
///  - обход российских сайтов (routing → direct для .ru и известных сервисов);
///  - фрагментацию TLS (обход DPI) через outbound "fragment".
///
/// Всё делается на чистом JSON, без внешних geo-файлов, чтобы работало на любом
/// устройстве без дополнительных ассетов.
library;

import 'dart:convert';

/// Стратегия выбора типа адреса.
enum IpStrategy {
  auto, // как отдаёт сервер (AsIs)
  ipv4, // только IPv4
  ipv6; // предпочитать IPv6

  String get domainStrategy => switch (this) {
        IpStrategy.auto => 'AsIs',
        IpStrategy.ipv4 => 'IPIfNonMatch',
        IpStrategy.ipv6 => 'IPIfNonMatch',
      };

  String get label => switch (this) {
        IpStrategy.auto => 'Авто',
        IpStrategy.ipv4 => 'IPv4',
        IpStrategy.ipv6 => 'IPv6',
      };
}

class NetOptions {
  final List<String> dns; // напр. ['1.1.1.1','8.8.8.8']; пусто = не трогаем
  final bool bypassRu; // российские сайты мимо VPN
  final IpStrategy ipStrategy;
  final bool fragment; // фрагментация TLS против DPI
  final List<String> directDomains; // пользовательские сайты в обход VPN (URL-split)

  const NetOptions({
    this.dns = const [],
    this.bypassRu = false,
    this.ipStrategy = IpStrategy.auto,
    this.fragment = false,
    this.directDomains = const [],
  });

  static const defaults = NetOptions();
}

/// Домены/сервисы, которые при включённом «обход RU» идут напрямую (mimo VPN).
/// Без geosite-файлов: суффикс .ru/.рф + крупные госсервисы и банки.
const _ruDirectDomains = <String>[
  'regexp:.*\\.ru\$',
  'regexp:.*\\.su\$',
  'regexp:.*\\.рф\$',
  'domain:gosuslugi.ru',
  'domain:nalog.ru',
  'domain:mos.ru',
  'domain:sberbank.ru',
  'domain:sber.ru',
  'domain:tinkoff.ru',
  'domain:vtb.ru',
  'domain:alfabank.ru',
  'domain:yandex.ru',
  'domain:vk.com',
  'domain:ok.ru',
  'domain:mail.ru',
  'domain:wildberries.ru',
  'domain:ozon.ru',
  'domain:avito.ru',
  'domain:2gis.ru',
  'domain:kinopoisk.ru',
];

/// ИИ-сервисы, которым нужен иностранный IP (всегда через туннель).
const _aiDomains = <String>[
  'domain:openai.com',
  'domain:chatgpt.com',
  'domain:oaistatic.com',
  'domain:oaiusercontent.com',
  'domain:gemini.google.com',
  'domain:bard.google.com',
  'domain:generativelanguage.googleapis.com',
  'domain:aistudio.google.com',
  'domain:anthropic.com',
  'domain:claude.ai',
  'domain:perplexity.ai',
  'domain:x.ai',
  'domain:grok.com',
  'domain:copilot.microsoft.com',
];

/// Возвращает изменённый JSON-конфиг (строку) с применёнными [opts].
String applyNetOptions(String baseConfig, NetOptions opts) {
  final Map<String, dynamic> cfg;
  try {
    cfg = jsonDecode(baseConfig) as Map<String, dynamic>;
  } catch (_) {
    return baseConfig; // не смогли распарсить — отдаём как есть
  }

  // --- DNS ---
  if (opts.dns.isNotEmpty) {
    cfg['dns'] = {
      'servers': opts.dns,
      'queryStrategy':
          opts.ipStrategy == IpStrategy.ipv4 ? 'UseIPv4' : 'UseIP',
    };
  }

  // --- routing / обход RU ---
  final outbounds = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];
  final hasDirect =
      outbounds.any((o) => (o as Map)['tag'] == 'direct');
  if (opts.bypassRu) {
    if (!hasDirect) {
      outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    }
    final routing = (cfg['routing'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    routing['domainStrategy'] = 'IPIfNonMatch';
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    // ИИ-домены ВСЕГДА через туннель (иностранный сервер), даже при обходе RU —
    // иначе ChatGPT/Gemini/Claude не открываются с российского IP. Правило идёт
    // ПЕРВЫМ, чтобы перебить возможный .ru-суффикс.
    String? proxyTag;
    for (final o in outbounds) {
      final tag = (o as Map)['tag'];
      if (tag != null && tag != 'direct' && tag != 'fragment') {
        proxyTag = tag as String;
        break;
      }
    }
    if (proxyTag != null) {
      rules.insert(0, {
        'type': 'field',
        'outboundTag': proxyTag,
        'domain': _aiDomains,
      });
    }
    rules.insert(1, {
      'type': 'field',
      'outboundTag': 'direct',
      'domain': _ruDirectDomains,
    });
    // Российские IP-подсети — если ядро без geoip, правило просто не сматчит.
    rules.insert(1, {
      'type': 'field',
      'outboundTag': 'direct',
      'ip': ['geoip:ru'],
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  // --- пользовательские сайты в обход VPN (URL-split) ---
  if (opts.directDomains.isNotEmpty) {
    if (!outbounds.any((o) => (o as Map)['tag'] == 'direct')) {
      outbounds.add({'protocol': 'freedom', 'tag': 'direct'});
    }
    final routing = (cfg['routing'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    routing['domainStrategy'] = 'IPIfNonMatch';
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    rules.insert(0, {
      'type': 'field',
      'outboundTag': 'direct',
      'domain': opts.directDomains.map((d) => 'domain:$d').toList(),
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  // --- IPv4/IPv6 стратегия (общая) ---
  if (opts.ipStrategy != IpStrategy.auto) {
    final routing = (cfg['routing'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    routing['domainStrategy'] = 'IPIfNonMatch';
    cfg['routing'] = routing;
  }

  // --- фрагментация против DPI ---
  if (opts.fragment) {
    // Оборачиваем реальный proxy-outbound в dialer с fragment: добавляем
    // отдельный freedom-fragment outbound и streamSettings.sockopt.dialerProxy.
    outbounds.add({
      'protocol': 'freedom',
      'tag': 'fragment',
      'settings': {
        'fragment': {
          'packets': 'tlshello',
          'length': '100-200',
          'interval': '10-20',
        }
      },
    });
    // основной proxy-outbound (первый, не direct/fragment) направляем через fragment
    for (final o in outbounds) {
      final m = o as Map;
      final tag = m['tag'];
      if (tag == 'direct' || tag == 'fragment') continue;
      final ss = (m['streamSettings'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final sockopt = (ss['sockopt'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      sockopt['dialerProxy'] = 'fragment';
      ss['sockopt'] = sockopt;
      m['streamSettings'] = ss;
      break;
    }
  }

  cfg['outbounds'] = outbounds;
  return jsonEncode(cfg);
}
