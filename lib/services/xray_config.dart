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
import '../platform.dart';

/// Проверочный адрес: пустой ответ 204 для проб связи и замера задержки.
///
/// ОБЫЧНЫЙ http, не https — и это важно. Через https добавляется рукопожатие
/// TLS с чужим CDN, и оно регулярно не укладывалось в таймаут: в логах ядра
/// «TLS handshake timeout», замер возвращал прочерк, а сторож считал живой
/// туннель мёртвым. Шифровать в пустом ответе нечего, а без рукопожатия
/// проверка втрое быстрее и заметно надёжнее.
const kProbeUrl = 'http://cp.cloudflare.com/generate_204';

/// Адреса для замера пинга, из которых человек выбирает в настройках.
///
/// Все — «страницы проверки связи»: отдают пустой ответ 204 без тела, поэтому
/// в число попадает только сетевая задержка, а не время отрисовки чужого
/// сайта. Все по обычному http: через https добавилось бы рукопожатие TLS с
/// самой проверочной точкой, и значения выросли бы на сотни миллисекунд
/// одинаково у всех серверов — для их сравнения это чистый шум.
///
/// Список, а не поле ввода: опечатка в адресе молча ломала все замеры, а
/// угадать подходящий адрес человек всё равно не может. Разные владельцы — на
/// случай, если чей-то домен у провайдера недоступен.
const kProbeUrls = <(String, String)>[
  ('Cloudflare', 'http://cp.cloudflare.com/generate_204'),
  ('Google', 'http://connectivitycheck.gstatic.com/generate_204'),
  ('Apple', 'http://captive.apple.com/hotspot-detect.html'),
  ('Microsoft', 'http://www.msftconnecttest.com/connecttest.txt'),
  ('Яндекс', 'http://yandex.ru/internet/204'),
];

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

  /// Мультиплексирование: несколько запросов идут по одному соединению вместо
  /// того, чтобы каждый раз открывать новое. Заметно ускоряет загрузку страниц
  /// с десятками мелких запросов; на скачивании больших файлов может, наоборот,
  /// чуть мешать — поэтому это переключатель, а не всегда включённое поведение.
  final bool mux;

  /// Локальная сеть (принтер, роутер, NAS, телевизор) идёт мимо туннеля.
  /// Без этого при включённом VPN устройства в домашней сети недоступны.
  final bool lanDirect;

  const NetOptions({
    this.dns = const [],
    this.bypassRu = false,
    this.ipStrategy = IpStrategy.auto,
    this.fragment = false,
    this.smartAi = true,
    this.adBlock = false,
    this.aiDomains = const [],
    this.ruDomains = const [],
    this.adDomains = const [],
    this.telegramOnly = false,
    this.mux = false,
    this.lanDirect = true,
  });

  static const defaults = NetOptions();
}

/// Использует ли outbound поток XTLS (`xtls-rprx-vision` и родственные).
///
/// С такими потоками нельзя включать мультиплексирование: соединение молча
/// обрывается. Проверяем всех пользователей во всех форматах настроек —
/// vnext (vless/vmess) и servers (trojan/ss).
bool _usesXtlsFlow(Map outbound) {
  final settings = outbound['settings'];
  if (settings is! Map) return false;
  for (final key in const ['vnext', 'servers']) {
    final list = settings[key];
    if (list is! List) continue;
    for (final entry in list) {
      if (entry is! Map) continue;
      final users = entry['users'];
      if (users is! List) continue;
      for (final u in users) {
        if (u is Map && '${u['flow'] ?? ''}'.startsWith('xtls')) return true;
      }
    }
  }
  return false;
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
  // Готовый список доменов OpenAI из geosite.dat — полнее, чем перечисление
  // руками, и обновляется вместе с ядром.
  'geosite:openai',
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
      for (final e in items) (e.contains(':') ? e : 'domain:$e'),
    ];

/// Базовый список рекламных/трекинговых доменов (когда панель не отдала свой).
///
/// Первым идёт geosite-список `category-ads-all` — он лежит прямо в сборке
/// (файл geosite.dat, 8 МБ) и содержит десятки тысяч рекламных и трекинговых
/// доменов. Мы его раньше не использовали и резали рекламу по двум десяткам
/// записей, набранных руками. Ручной список оставлен ниже как подстраховка:
/// в нём русские сети, которых в международном списке может не быть.
const _defaultAdDomains = <String>[
  'geosite:category-ads-all',
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

/// Адреса, по которым приложение проверяет, что туннель реально несёт трафик.
/// Пустые ответы 204, ничего не весят. В бесплатном режиме их обязательно надо
/// пускать через туннель — иначе проверить его работоспособность нечем.
const _probeDomains = <String>[
  'domain:gstatic.com',
  'domain:cp.cloudflare.com',
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
/// Убирает из правил ссылки на geosite/geoip, если списков в ядре нет.
///
/// Xray при неизвестном списке не пропускает правило, а ОТКАЗЫВАЕТСЯ
/// СТАРТОВАТЬ. Поэтому на платформе без .dat-файлов такие записи надо вычистить
/// заранее: правила останутся работать по явным доменам, перечисленным рядом с
/// каждым списком именно на этот случай.
///
/// Правило, от которого после чистки не осталось условий, выбрасывается
/// целиком: пустое условие в Xray означает «подходит всё», и правило,
/// задуманное как «реклама — в блок», заблокировало бы весь трафик.
void stripGeoRules(Map<String, dynamic> cfg) {
  final routing = cfg['routing'];
  if (routing is! Map) return;
  final rules = routing['rules'];
  if (rules is! List) return;

  bool isGeo(Object? v) =>
      v is String && (v.startsWith('geosite:') || v.startsWith('geoip:'));

  final kept = <dynamic>[];
  for (final rule in rules) {
    if (rule is! Map) {
      kept.add(rule);
      continue;
    }
    var hadSelector = false;
    for (final key in const ['domain', 'ip']) {
      final list = rule[key];
      if (list is! List) continue;
      hadSelector = true;
      final clean = list.where((e) => !isGeo(e)).toList();
      if (clean.isEmpty) {
        rule.remove(key);
      } else {
        rule[key] = clean;
      }
    }
    // Условия были и все вычистились — правило потеряло смысл.
    final stillHas = rule.containsKey('domain') ||
        rule.containsKey('ip') ||
        rule.containsKey('port') ||
        rule.containsKey('protocol') ||
        rule.containsKey('network');
    if (hadSelector && !stillHas) continue;
    kept.add(rule);
  }
  routing['rules'] = kept;
}

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
      outs.add(<String, dynamic>{'protocol': 'blackhole', 'tag': 'blocked'});
    }
    String? pTag;
    for (final o in outs) {
      final tag = (o as Map)['tag'];
      if (tag != null &&
          tag != 'direct' &&
          tag != 'fragment' &&
          tag != 'blocked') {
        pTag = tag as String;
        break;
      }
    }
    final proxy = pTag ?? 'proxy';
    cfg['outbounds'] = outs;
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
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
      // Адреса проверки связи — тоже через туннель. Без этого приложение не
      // может убедиться, что бесплатный туннель ЖИВОЙ: проба уходила в
      // blackhole и любой ответ был неотличим от мёртвого сервера. Из-за этого
      // free-режим включался «успешно» на нерабочем сервере, а Telegram не
      // грузился. Это два пустых 204-ответа, трафика они не несут.
      {'type': 'field', 'outboundTag': proxy, 'domain': _probeDomains},
      // всё остальное — в никуда (у других приложений интернета нет)
      {'type': 'field', 'outboundTag': 'blocked', 'network': 'tcp,udp'},
    ];
    cfg['routing'] = routing;
    if (!Caps.geoAssets) stripGeoRules(cfg);
    return jsonEncode(cfg); // прочие опции в бесплатном режиме не применяем
  }
  // Динамические списки из панели (если пусты — встроенные дефолты).
  final aiList = opts.aiDomains.isNotEmpty ? _norm(opts.aiDomains) : _aiDomains;
  final ruList =
      opts.ruDomains.isNotEmpty ? _norm(opts.ruDomains) : _ruDirectDomains;
  final adList =
      _norm(opts.adDomains.isNotEmpty ? opts.adDomains : _defaultAdDomains);

  // --- РАСПОЗНАВАНИЕ ДОМЕНОВ (sniffing) ---
  //
  // Без него ВСЕ доменные правила бесполезны, и это не преувеличение.
  //
  // В режиме туннеля приложение получает IP-пакеты: до ядра доходит адрес
  // назначения, но не имя сайта. Правила вида «openai.com → через прокси» или
  // «реклама → в никуда» сравнивать не с чем, и они не срабатывают никогда.
  // Sniffing достаёт имя из рукопожатия TLS, заголовка HTTP и QUIC — только
  // после этого доменная маршрутизация начинает работать.
  //
  // Ядро отдаёт конфиг из share-ссылки с выключенным sniffing, поэтому
  // включаем его сами. У подписок-конфигов он обычно уже включён — тогда
  // ничего не меняем.
  final inbounds = (cfg['inbounds'] as List?)?.cast<dynamic>() ?? [];
  for (final i in inbounds) {
    if (i is! Map) continue;
    final proto = '${i['protocol'] ?? ''}'.toLowerCase();
    if (proto != 'socks' && proto != 'http') continue;
    final sn = <String, dynamic>{
      ...?(i['sniffing'] as Map?)?.cast<String, dynamic>(),
    };
    if (sn['enabled'] == true) continue; // сервис уже позаботился
    sn['enabled'] = true;
    sn['destOverride'] = const ['http', 'tls', 'quic'];
    // routeOnly=false: подменяем адрес назначения на распознанный домен, иначе
    // соединение уйдёт на исходный IP в обход правил.
    sn['routeOnly'] = false;
    i['sniffing'] = sn;
  }
  if (inbounds.isNotEmpty) cfg['inbounds'] = inbounds;

  // --- DNS и версия сети ---
  //
  // Раньше выбор версии сети применялся ТОЛЬКО вместе со своим DNS: если
  // человек выбрал «только IPv4», но DNS не менял, настройка не делала ничего.
  // Теперь стратегия запроса адресов задаётся всегда, а свои серверы DNS —
  // отдельно и по желанию.
  final queryStrategy = switch (opts.ipStrategy) {
    IpStrategy.ipv4 => 'UseIPv4',
    IpStrategy.ipv6 => 'UseIPv6',
    IpStrategy.auto => 'UseIP',
  };
  if (opts.dns.isNotEmpty || opts.ipStrategy != IpStrategy.auto) {
    final dnsBlock = (cfg['dns'] as Map<String, dynamic>?) ?? {};
    if (opts.dns.isNotEmpty) dnsBlock['servers'] = opts.dns;
    // Сервис мог прислать свои серверы DNS в конфиге — не выбрасываем их.
    dnsBlock['servers'] ??= ['1.1.1.1', '8.8.8.8'];
    dnsBlock['queryStrategy'] = queryStrategy;
    cfg['dns'] = dnsBlock;
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
      outbounds.add(<String, dynamic>{'protocol': 'freedom', 'tag': 'direct'});
    }
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
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
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    rules.insert(0, {
      'type': 'field',
      'outboundTag': proxyTag,
      'domain': aiList,
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  // --- локальная сеть мимо туннеля ---
  // Приватные диапазоны (домашний роутер, принтер, NAS) + сам loopback.
  // Правило идёт ПОСЛЕ ИИ/RU, но раньше общего маршрута, поэтому локальные
  // адреса всегда уходят напрямую.
  if (opts.lanDirect) {
    if (!outbounds.any((o) => (o as Map)['tag'] == 'direct')) {
      outbounds.add(<String, dynamic>{'protocol': 'freedom', 'tag': 'direct'});
    }
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final rules = (routing['rules'] as List?)?.cast<dynamic>() ?? [];
    rules.insert(0, {
      'type': 'field',
      'outboundTag': 'direct',
      'ip': ['geoip:private'],
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  // --- мультиплексирование ---
  // Вешаем на КАЖДЫЙ прокси-outbound (не на direct/blackhole — там оно
  // бессмысленно и ломает прямой трафик).
  if (opts.mux) {
    for (final o in outbounds) {
      final m = o as Map;
      final tag = m['tag'];
      final proto = m['protocol'];
      if (tag == 'direct' || tag == 'blocked' || tag == 'fragment') continue;
      if (proto == 'freedom' || proto == 'blackhole' || proto == 'dns') {
        continue;
      }
      // КРИТИЧНО: мультиплексирование НЕСОВМЕСТИМО с потоком XTLS Vision.
      // Ядро принимает такой конфиг молча, туннель поднимается, запросы
      // уходят — и обрываются: «connection closed», скачано ноль. Проверено
      // на живом сервере: тот же конфиг без mux отдаёт 204, с mux — ничего.
      // Почти все серверы Reality идут именно с flow=xtls-rprx-vision,
      // поэтому включённое ускорение убивало VPN целиком.
      if (_usesXtlsFlow(m)) continue;
      // Hysteria мультиплексирует потоки сама, средствами QUIC. Свой mux
      // поверх — второй слой поверх того же механизма: лишние заголовки и
      // потерянная скорость там, где вся суть протокола именно в скорости.
      if (proto == 'hysteria') continue;
      m['mux'] = {'enabled': true, 'concurrency': 8};
    }
  }

  // --- AdBlock: реклама/трекеры → blackhole (режутся прямо на устройстве) ---
  if (opts.adBlock && adList.isNotEmpty) {
    if (!outbounds.any((o) => (o as Map)['tag'] == 'blocked')) {
      outbounds.add(<String, dynamic>{'protocol': 'blackhole', 'tag': 'blocked'});
    }
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
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

  // --- IPv4/IPv6: прямые соединения тоже обязаны слушаться настройки ---
  //
  // Прежний код ставил domainStrategy в 'IPIfNonMatch' — ровно то же значение,
  // что стоит по умолчанию. Настройка формально «применялась» и не меняла
  // ничего. Реально версию сети в Xray задаёт domainStrategy у freedom-выходов
  // и queryStrategy у DNS (см. выше).
  if (opts.ipStrategy != IpStrategy.auto) {
    final routing =
        (cfg['routing'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    routing['domainStrategy'] = 'IPIfNonMatch';
    cfg['routing'] = routing;
    for (final o in outbounds) {
      if (o is! Map) continue;
      if (o['protocol'] != 'freedom') continue;
      // Пересобираем словарь: пришедший из чужого конфига может иметь узкий
      // тип значений, и вложенный объект в него просто не записать.
      final st = <String, dynamic>{
        ...?(o['settings'] as Map?)?.cast<String, dynamic>(),
        'domainStrategy': queryStrategy,
      };
      o['settings'] = st;
    }
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
      final ss =
          (m['streamSettings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final sockopt =
          (ss['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (sockopt['dialerProxy'] != null) {
        continue; // уже звено цепочки — пропускаем
      }
      sockopt['dialerProxy'] = 'fragment';
      ss['sockopt'] = sockopt;
      m['streamSettings'] = ss;
      break;
    }
  }

  cfg['outbounds'] = outbounds;
  if (!Caps.geoAssets) stripGeoRules(cfg);
  return jsonEncode(cfg);
}
