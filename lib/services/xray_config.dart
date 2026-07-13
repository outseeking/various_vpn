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

import '../l10n.dart';

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
        IpStrategy.auto => L.t('ip_auto'),
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
  final bool smartAi; // умный доступ к ИИ: домены ИИ всегда через туннель
  final bool adBlock; // блокировка рекламы/трекеров на уровне туннеля
  // Динамические списки из панели (если пусто — берём встроенные дефолты).
  final List<String> aiDomains;
  final List<String> ruDomains;
  final List<String> adDomains;
  // Бесплатный режим: через туннель идёт ТОЛЬКО Telegram, всё остальное —
  // напрямую (мимо VPN). Реализовано роутингом Xray (не зависит от списка
  // установленных приложений — раньше при пустом списке туннелировалось всё).
  final bool telegramOnly;

  const NetOptions({
    this.dns = const [],
    this.bypassRu = false,
    this.ipStrategy = IpStrategy.auto,
    this.fragment = false,
    this.directDomains = const [],
    this.smartAi = true,
    this.adBlock = false,
    this.aiDomains = const [],
    this.ruDomains = const [],
    this.adDomains = const [],
    this.telegramOnly = false,
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

/// Нормализует запись домена для Xray: голый домен → domain:X, а записи с
/// префиксом (domain:/regexp:/geosite:/full:) оставляет как есть.
List<String> _norm(List<String> items) => [
      for (final e in items)
        (e.contains(':') ? e : 'domain:$e'),
    ];

/// Базовый список рекламных/трекинговых доменов (когда панель не отдала свой).
/// Короткий, но покрывает крупные рекламные/аналитические сети.
const _defaultAdDomains = <String>[
  'domain:doubleclick.net',
  'domain:googlesyndication.com',
  'domain:googleadservices.com',
  'domain:google-analytics.com',
  'domain:adservice.google.com',
  'domain:ads.yahoo.com',
  'domain:adnxs.com',
  'domain:advertising.com',
  'domain:scorecardresearch.com',
  'domain:mc.yandex.ru',
  'domain:an.yandex.ru',
  'domain:ads.vk.com',
  'domain:criteo.com',
  'domain:taboola.com',
  'domain:outbrain.com',
  'domain:appsflyer.com',
  'domain:adjust.com',
  'domain:branch.io',
  'domain:amplitude.com',
  'domain:app-measurement.com',
];

/// Домены Telegram (для бесплатного режима «только Telegram»).
const _telegramDomains = <String>[
  'domain:telegram.org',
  'domain:t.me',
  'domain:telegram.me',
  'domain:telegram.dog',
  'domain:telegra.ph',
  'domain:telesco.pe',
  'domain:tdesktop.com',
  'domain:cdn-telegram.org',
  'domain:comments.app',
];

/// Домены/IP нашей инфраструктуры подписки (панель + субсервер /vsub). В
/// бесплатном режиме их тоже пускаем через туннель — иначе запрос подписки
/// уходит в blackhole вместе с остальным не-Telegram трафиком и подписку
/// невозможно активировать, не выключив бесплатный VPN.
const _subDomains = <String>[
  'domain:ug-connect.site', // nl1.ug-connect.site:8088/vsub и др. поддомены
];
const _subIps = <String>[
  '91.236.186.75/32', // админ-панель (прямой IP, http://91.236.186.75:8080/vsub)
];

/// IP-подсети дата-центров Telegram (MTProto ходит прямо на IP, поэтому одних
/// доменов мало — маршрутизируем и по CIDR). Список публичный (AS62041/62014).
const _telegramCidrs = <String>[
  '91.108.4.0/22',
  '91.108.8.0/22',
  '91.108.12.0/22',
  '91.108.16.0/22',
  '91.108.20.0/22',
  '91.108.56.0/22',
  '91.105.192.0/23',
  '149.154.160.0/20',
  '185.76.151.0/24',
  '2001:b28:f23d::/48',
  '2001:b28:f23f::/48',
  '2001:67c:4e8::/48',
  '2a0a:f280::/32',
];

/// Возвращает изменённый JSON-конфиг (строку) с применёнными [opts].
String applyNetOptions(String baseConfig, NetOptions opts) {
  final Map<String, dynamic> cfg;
  try {
    cfg = jsonDecode(baseConfig) as Map<String, dynamic>;
  } catch (_) {
    return baseConfig; // не смогли распарсить — отдаём как есть
  }

  // --- БЕСПЛАТНЫЙ РЕЖИМ: РАБОТАЕТ ТОЛЬКО Telegram ---
  // Реализовано роутингом Xray (надёжно, не зависит от списка приложений):
  //   • DNS (порт 53) → proxy — чтобы имена Telegram резолвились через туннель;
  //   • домены/IP Telegram → proxy;
  //   • ВСЁ остальное → blackhole (blocked) — у других приложений интернета НЕТ.
  // Так на бесплатной версии реально работает только Telegram (сайты/Яндекс и
  // прочее не грузятся), что и мотивирует купить полную подписку.
  if (opts.telegramOnly) {
    final outs = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];
    if (!outs.any((o) => (o as Map)['tag'] == 'blocked')) {
      outs.add({'protocol': 'blackhole', 'tag': 'blocked'});
    }
    String? pTag;
    for (final o in outs) {
      final tag = (o as Map)['tag'];
      if (tag != null && tag != 'direct' && tag != 'fragment' && tag != 'blocked') {
        pTag = tag as String;
        break;
      }
    }
    final proxy = pTag ?? 'proxy';
    cfg['outbounds'] = outs;
    final routing = (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    routing['domainStrategy'] = 'IPIfNonMatch';
    routing['rules'] = [
      // DNS через туннель — иначе домены Telegram не резолвятся
      {'type': 'field', 'outboundTag': proxy, 'port': '53'},
      // Наша подписка (панель + субсервер /vsub) — через туннель, чтобы её
      // можно было активировать, не выключая бесплатный VPN.
      {'type': 'field', 'outboundTag': proxy, 'domain': _subDomains},
      {'type': 'field', 'outboundTag': proxy, 'ip': _subIps},
      {'type': 'field', 'outboundTag': proxy, 'domain': _telegramDomains},
      {'type': 'field', 'outboundTag': proxy, 'ip': _telegramCidrs},
      // всё остальное — в никуда (у других приложений интернета нет)
      {'type': 'field', 'outboundTag': 'blocked', 'network': 'tcp,udp'},
    ];
    cfg['routing'] = routing;
    return jsonEncode(cfg); // прочие опции в бесплатном режиме не применяем
  }
  // Динамические списки из панели (если пусты — встроенные дефолты).
  final aiList = opts.aiDomains.isNotEmpty ? _norm(opts.aiDomains) : _aiDomains;
  final ruList =
      opts.ruDomains.isNotEmpty ? _norm(opts.ruDomains) : _ruDirectDomains;
  final adList = _norm(opts.adDomains.isNotEmpty ? opts.adDomains : _defaultAdDomains);

  // --- DNS ---
  if (opts.dns.isNotEmpty) {
    cfg['dns'] = {
      'servers': opts.dns,
      'queryStrategy':
          opts.ipStrategy == IpStrategy.ipv4 ? 'UseIPv4' : 'UseIP',
    };
  }

  // --- routing / обход RU + умный ИИ ---
  final outbounds = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];
  // тег основного proxy-outbound (через него гоним ИИ-домены)
  String? proxyTag;
  for (final o in outbounds) {
    final tag = (o as Map)['tag'];
    if (tag != null && tag != 'direct' && tag != 'fragment') {
      proxyTag = tag as String;
      break;
    }
  }

  if (opts.bypassRu) {
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
      'domain': ruList,
    });
    // Российские IP-подсети — если ядро без geoip, правило просто не сматчит.
    rules.insert(0, {
      'type': 'field',
      'outboundTag': 'direct',
      'ip': ['geoip:ru'],
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  // --- умный доступ к ИИ: домены ChatGPT/Gemini/Claude и т.п. ВСЕГДА через
  // туннель (иностранный сервер), перебивая .ru-суффикс и обход RU. Правило
  // вставляется ПЕРВЫМ, поэтому имеет наивысший приоритет. Работает независимо
  // от «обхода RU» — иначе ИИ не открывается с российского IP. ---
  if (opts.smartAi && proxyTag != null) {
    final routing = (cfg['routing'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    rules.insert(0, {
      'type': 'field',
      'outboundTag': proxyTag,
      'domain': aiList,
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

  // --- AdBlock: реклама/трекеры → blackhole (режутся прямо на устройстве) ---
  if (opts.adBlock && adList.isNotEmpty) {
    if (!outbounds.any((o) => (o as Map)['tag'] == 'blocked')) {
      outbounds.add({'protocol': 'blackhole', 'tag': 'blocked'});
    }
    final routing = (cfg['routing'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    routing['domainStrategy'] ??= 'IPIfNonMatch';
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    // после ИИ-правила, но раньше общих: рекламу глушим всегда
    rules.add({
      'type': 'field',
      'outboundTag': 'blocked',
      'domain': adList,
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
    // Фрагментацию вешаем на САМЫЙ ВНУТРЕННИЙ proxy-outbound — тот, у которого
    // ещё НЕТ dialerProxy. В обычном режиме это единственный proxy; в мультихопе
    // (exit.dialerProxy='entry') это входная нода — так цепочка не рвётся:
    // app → fragment → entry → exit.
    for (final o in outbounds) {
      final m = o as Map;
      final tag = m['tag'];
      if (tag == 'direct' || tag == 'fragment' || tag == 'blocked') continue;
      final ss = (m['streamSettings'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final sockopt = (ss['sockopt'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      if (sockopt['dialerProxy'] != null) continue; // уже звено цепочки — пропускаем
      sockopt['dialerProxy'] = 'fragment';
      ss['sockopt'] = sockopt;
      m['streamSettings'] = ss;
      break;
    }
  }

  cfg['outbounds'] = outbounds;
  return jsonEncode(cfg);
}
