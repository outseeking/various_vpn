/// Модель одного VPN-сервера, разобранного из subscription-ссылки.
///
/// Важное: поле [raw] хранит исходную share-ссылку (vless://..., hysteria2://...)
/// в неизменном виде — именно её мы передаём в нативное VPN-ядро (Xray/sing-box),
/// которое само умеет её парсить. Остальные поля разбираем для отображения в UI
/// и для логики выбора сервера (страна, протокол, пинг).
library;

import '../l10n.dart';

enum VpnProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  hysteria,
  hysteria2,
  tuic,
  wireguard,
  anytls,
  socks,
  unknown;

  /// Узнаваемое имя протокола для UI.
  String get label => switch (this) {
        VpnProtocol.vless => 'VLESS',
        VpnProtocol.vmess => 'VMess',
        VpnProtocol.trojan => 'Trojan',
        VpnProtocol.shadowsocks => 'Shadowsocks',
        VpnProtocol.hysteria => 'Hysteria',
        VpnProtocol.hysteria2 => 'Hysteria2',
        VpnProtocol.tuic => 'TUIC',
        VpnProtocol.wireguard => 'WireGuard',
        VpnProtocol.anytls => 'AnyTLS',
        VpnProtocol.socks => 'SOCKS',
        VpnProtocol.unknown => 'Unknown',
      };

  static VpnProtocol fromScheme(String scheme) =>
      switch (scheme.toLowerCase()) {
        'vless' => VpnProtocol.vless,
        'vmess' => VpnProtocol.vmess,
        'trojan' || 'trojan-go' => VpnProtocol.trojan,
        'ss' || 'shadowsocks' => VpnProtocol.shadowsocks,
        // hy/hysteria без цифры — это первая версия, у неё свой формат
        // рукопожатия; hy2/hysteria2 — вторая. Путать их нельзя.
        'hysteria' || 'hy' => VpnProtocol.hysteria,
        'hysteria2' || 'hy2' => VpnProtocol.hysteria2,
        'tuic' => VpnProtocol.tuic,
        'wg' || 'wireguard' => VpnProtocol.wireguard,
        'anytls' => VpnProtocol.anytls,
        'socks' || 'socks5' => VpnProtocol.socks,
        // http/https НЕ распознаём как протокол сервера: подписка сплошь и
        // рядом содержит обычные ссылки (на панель, на сайт, на другую
        // подписку), и они превращались бы в фантомные «серверы».
        _ => VpnProtocol.unknown,
      };
}

class VpnServer {
  final VpnProtocol protocol;
  final String name; // ремарка (часто страна/город)
  final String address; // хост
  final int port;
  final String raw; // исходная share-ссылка целиком — для VPN-ядра
  final Map<String, String> params; // query-параметры (sni, pbk, ...)

  /// Готовый конфиг ядра целиком, если сервер пришёл из подписки-конфига
  /// (формат v2rayN / sing-box / Clash), а не share-ссылкой.
  ///
  /// Такие подписки несут не только адрес сервера, но и собственную
  /// маршрутизацию, DNS и балансировщики. Если строить конфиг заново по ссылке,
  /// всё это теряется — сервис работает не так, как задумал его владелец.
  /// Поэтому исходный конфиг сохраняем и отдаём ядру как есть.
  String? fullConfig;

  /// Пинг в мс. -1 = ещё не измерялся, null невозможен (для простоты UI).
  int pingMs;

  /// Каким методом получено текущее значение [pingMs]: 'tcp' | 'proxy' | ''.
  ///
  /// Без этого значения разных методов смешивались в одном списке: человек
  /// переключал замер на «через прокси», часть серверов перемерялась, а на
  /// остальных висели старые TCP-числа — выглядело так, будто настройка
  /// применилась не ко всем и «слетает».
  String pingVia = '';

  /// Человекочитаемое имя для UI — страна (+ номер, если их несколько в одной).
  /// Проставляется в AppState после импорта (там видны «соседи»). Пусто = берём
  /// [countryName].
  String displayName;

  /// Когда сервер в последний раз подключился, но трафик через него не пошёл.
  ///
  /// Отдельно от пинга: до мёртвого сервера пинг нередко проходит — отвечает
  /// балансировщик, за которым уже ничего нет.
  ///
  /// Метка ВРЕМЕННАЯ и сама протухает: сервер мог моргнуть на минуту, а
  /// вечная метка навсегда выбрасывала бы его из выбора — из-за этого
  /// «лучшим» становился случайный сервер без замера вместо быстрого.
  DateTime? deadAt;

  static const _deadFor = Duration(minutes: 5);

  bool get unreachable =>
      deadAt != null && DateTime.now().difference(deadAt!) < _deadFor;

  set unreachable(bool v) => deadAt = v ? DateTime.now() : null;

  /// Сервер пришёл из ЧУЖОЙ подписки (не нашей панели). Такие серверы работают
  /// без нашей подписки — приложение выступает обычным клиентом, — но и наши
  /// платные серверы ими не открываются: доступ к ним считается отдельно.
  bool foreign;

  VpnServer({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
    required this.raw,
    Map<String, String>? params,
    this.fullConfig,
    this.pingMs = -1,
    this.displayName = '',
    this.foreign = false,
  }) : params = params ?? const {};

  /// Имя сервера для рукопожатия TLS (SNI).
  ///
  /// Нужно точному замеру пинга: у Reality-серверов адрес обычно голый IP, и
  /// без имени сервер рукопожатие не завершает. Берём из параметров ссылки, а
  /// если их нет — из адреса (для обычного TLS этого достаточно).
  String get sni {
    for (final key in const ['sni', 'peer', 'host', 'serverName']) {
      final v = params[key];
      if (v != null && v.isNotEmpty) return v.split(',').first.trim();
    }
    return address;
  }

  /// Стабильный идентификатор сервера (для правил per-app и хранилища).
  ///
  /// В нём обязан участвовать САМ КОНФИГ, а не только адрес. В подписках сплошь
  /// и рядом несколько записей ведут на один хост и порт, отличаясь транспортом
  /// или ключом («Автовыбор | Wi-Fi 2», «…4», «…6»). При id вида
  /// `протокол://адрес:порт` они получали ОДИНАКОВЫЙ идентификатор, и дальше
  /// ломалось всё, что на него опирается: в шапке был один сервер, а галочка
  /// стояла на другом; список с одинаковыми ключами отказывался
  /// перетаскиваться; выбор сервера попадал не туда.
  String get id => '${protocol.name}://$address:$port#${_rawHash()}';

  /// Короткая устойчивая подпись ссылки. Нужна только для различения записей,
  /// поэтому криптостойкость не требуется — важна стабильность между запусками.
  String _rawHash() {
    var h = 0x811c9dc5;
    for (final c in raw.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  /// Поддерживается ли протокол текущим ядром (Xray).
  ///
  /// Hysteria появилась здесь после перехода на свежую сборку ядра: в ней есть
  /// proxy/hysteria, и отдельный движок для неё не нужен. TUIC и WireGuard
  /// Xray по-прежнему не умеет — такие серверы не показываем и не выбираем для
  /// автоподключения, иначе человек ткнул бы в сервер и получил молчаливый
  /// отказ.
  bool get xraySupported => const {
        VpnProtocol.vless,
        VpnProtocol.vmess,
        VpnProtocol.trojan,
        VpnProtocol.shadowsocks,
        VpnProtocol.hysteria,
        VpnProtocol.hysteria2,
      }.contains(protocol);

  /// Приоритет транспорта для автоподключения (меньше = лучше). На Android
  /// транспорт httpupgrade падает с "bad file descriptor" (проблема protect
  /// сокета), поэтому его — в конец. Reality самый надёжный.
  int get transportPriority {
    final r = raw.toLowerCase();
    if (r.contains('security=reality')) return 0;
    // Hysteria идёт по UDP/QUIC. Там, где провайдер режет UDP, она не встанет
    // вовсе — поэтому автовыбор предпочитает ей обычный TCP-транспорт, но
    // ставит выше проблемного httpupgrade.
    if (protocol == VpnProtocol.hysteria ||
        protocol == VpnProtocol.hysteria2) {
      return 1;
    }
    if (r.contains('type=httpupgrade') || r.contains('type=ws')) return 2;
    return 1; // обычный tcp/grpc/tls
  }

  /// Транспорт из raw-ссылки: reality/tls + tcp/grpc/ws — для показа под сервером.
  /// Напр. «VLESS · Reality · gRPC» или «VLESS · TLS · TCP».
  String get transportLabel {
    final r = raw.toLowerCase();
    final parts = <String>[protocol.label];
    // Hysteria — это всегда QUIC поверх TLS, вариантов транспорта у неё нет,
    // и в ссылке type= не пишут. Собираем подпись отдельно.
    if (protocol == VpnProtocol.hysteria || protocol == VpnProtocol.hysteria2) {
      return '${protocol.label} · QUIC';
    }
    if (r.contains('security=reality')) {
      parts.add('Reality');
    } else if (r.contains('security=tls')) {
      parts.add('TLS');
    }
    const transports = {
      'grpc': 'gRPC',
      'httpupgrade': 'HTTPUpgrade',
      'splithttp': 'SplitHTTP',
      'xhttp': 'XHTTP',
      'quic': 'QUIC',
      'kcp': 'mKCP',
      'ws': 'WS',
      'h2': 'HTTP/2',
      'tcp': 'TCP',
    };
    for (final e in transports.entries) {
      if (r.contains('type=${e.key}')) {
        parts.add(e.value);
        return parts.join(' · ');
      }
    }
    // В ссылке без явного type транспорт по умолчанию — TCP.
    if (protocol == VpnProtocol.vless || protocol == VpnProtocol.trojan) {
      parts.add('TCP');
    }
    return parts.join(' · ');
  }

  /// Имя для показа: страна (или ремарка, если страну не определили).
  String get title => displayName.isNotEmpty ? displayName : countryName;

  /// Название страны на языке интерфейса (или очищенная ремарка, если страну
  /// не определили). Из ремарки убираем флаг-эмодзи/лишние значки.
  String get countryName {
    final en = L.current == 'en';
    final n = _countryNames[countryCode];
    if (n != null) return en ? n[1] : n[0];
    return _cleanRemark(name);
  }

  /// Двухбуквенный код страны, выведенный из имени/домена. Пустая строка, если
  /// не удалось определить.
  String get countryCode => _guessCountry(name, address);

  /// Флаг-эмодзи по коду страны (или 🌐, если неизвестно).
  String get flag {
    final cc = countryCode;
    if (cc.length != 2) return '🌐';
    const base = 0x1F1E6;
    final a = cc.codeUnitAt(0) - 0x41 + base;
    final b = cc.codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes([a, b]);
  }

  @override
  String toString() => '$flag $name (${protocol.label}) $address:$port';
}

/// IP наших серверов → код страны (надёжно для нашего деплоя; ремарки в
/// подписке часто содержат маскировочные SNI-домены и стране не соответствуют).
const _knownServerIps = {
  '91.236.186.75': 'DE',
  '132.243.224.220': 'DE',
  '89.125.17.116': 'NL',
  '87.58.204.230': 'FI',
};

/// Публичный список IP наших серверов — чтобы приложение принимало ТОЛЬКО наши
/// подписки (в т.ч. когда конфиги заданы по IP, а не по домену).
const knownServerIps = <String>{
  '91.236.186.75',
  '132.243.224.220',
  '89.125.17.116',
  '87.58.204.230',
};

/// Локализованные названия стран [ru, en] по ISO-коду.
const _countryNames = <String, List<String>>{
  'DE': ['Германия', 'Germany'],
  'NL': ['Нидерланды', 'Netherlands'],
  'FI': ['Финляндия', 'Finland'],
  'RU': ['Россия', 'Russia'],
  'US': ['США', 'USA'],
  'GB': ['Великобритания', 'United Kingdom'],
  'PL': ['Польша', 'Poland'],
  'FR': ['Франция', 'France'],
  'IT': ['Италия', 'Italy'],
  'ES': ['Испания', 'Spain'],
  'SE': ['Швеция', 'Sweden'],
  'NO': ['Норвегия', 'Norway'],
  'CH': ['Швейцария', 'Switzerland'],
  'AT': ['Австрия', 'Austria'],
  'TR': ['Турция', 'Turkey'],
  'UA': ['Украина', 'Ukraine'],
  'JP': ['Япония', 'Japan'],
  'SG': ['Сингапур', 'Singapore'],
  'HK': ['Гонконг', 'Hong Kong'],
  'KZ': ['Казахстан', 'Kazakhstan'],
  'AE': ['ОАЭ', 'UAE'],
  'CA': ['Канада', 'Canada'],
  'IN': ['Индия', 'India'],
  'CZ': ['Чехия', 'Czechia'],
  'RO': ['Румыния', 'Romania'],
  'LT': ['Литва', 'Lithuania'],
  'LV': ['Латвия', 'Latvia'],
  'EE': ['Эстония', 'Estonia'],
  'BG': ['Болгария', 'Bulgaria'],
  'MD': ['Молдова', 'Moldova'],
  'BE': ['Бельгия', 'Belgium'],
  'DK': ['Дания', 'Denmark'],
  'IE': ['Ирландия', 'Ireland'],
  'PT': ['Португалия', 'Portugal'],
  'IL': ['Израиль', 'Israel'],
  'AU': ['Австралия', 'Australia'],
  'BR': ['Бразилия', 'Brazil'],
  'CN': ['Китай', 'China'],
  'KR': ['Корея', 'Korea'],
  'AM': ['Армения', 'Armenia'],
  'GE': ['Грузия', 'Georgia'],
  'MC': ['Монако', 'Monaco'],
  'HU': ['Венгрия', 'Hungary'],
  'SK': ['Словакия', 'Slovakia'],
  'SI': ['Словения', 'Slovenia'],
  'HR': ['Хорватия', 'Croatia'],
  'RS': ['Сербия', 'Serbia'],
  'GR': ['Греция', 'Greece'],
  'CY': ['Кипр', 'Cyprus'],
  'IS': ['Исландия', 'Iceland'],
  'LU': ['Люксембург', 'Luxembourg'],
  'MT': ['Мальта', 'Malta'],
  'AL': ['Албания', 'Albania'],
  'MK': ['Северная Македония', 'North Macedonia'],
  'BA': ['Босния', 'Bosnia'],
  'ME': ['Черногория', 'Montenegro'],
  'BY': ['Беларусь', 'Belarus'],
  'AZ': ['Азербайджан', 'Azerbaijan'],
  'UZ': ['Узбекистан', 'Uzbekistan'],
  'KG': ['Киргизия', 'Kyrgyzstan'],
  'TJ': ['Таджикистан', 'Tajikistan'],
  'MN': ['Монголия', 'Mongolia'],
  'TH': ['Таиланд', 'Thailand'],
  'VN': ['Вьетнам', 'Vietnam'],
  'MY': ['Малайзия', 'Malaysia'],
  'ID': ['Индонезия', 'Indonesia'],
  'PH': ['Филиппины', 'Philippines'],
  'TW': ['Тайвань', 'Taiwan'],
  'PK': ['Пакистан', 'Pakistan'],
  'BD': ['Бангладеш', 'Bangladesh'],
  'SA': ['Саудовская Аравия', 'Saudi Arabia'],
  'QA': ['Катар', 'Qatar'],
  'KW': ['Кувейт', 'Kuwait'],
  'BH': ['Бахрейн', 'Bahrain'],
  'OM': ['Оман', 'Oman'],
  'IR': ['Иран', 'Iran'],
  'IQ': ['Ирак', 'Iraq'],
  'EG': ['Египет', 'Egypt'],
  'ZA': ['ЮАР', 'South Africa'],
  'NG': ['Нигерия', 'Nigeria'],
  'KE': ['Кения', 'Kenya'],
  'MA': ['Марокко', 'Morocco'],
  'MX': ['Мексика', 'Mexico'],
  'AR': ['Аргентина', 'Argentina'],
  'CL': ['Чили', 'Chile'],
  'CO': ['Колумбия', 'Colombia'],
  'PE': ['Перу', 'Peru'],
  'NZ': ['Новая Зеландия', 'New Zealand'],
};

/// Все известные приложению страны. Нужен проверке флагов: она рисует их все
/// разом, поэтому страна без флага обнаруживается сразу, а не у пользователя.
Iterable<String> get countryCodes => _countryNames.keys;

/// Название страны по коду на языке интерфейса. Пусто, если код неизвестен.
/// Нужно там, где страна берётся не из сервера, — например подпись точки
/// «откуда идёт трафик» на глобусе.
String countryLabel(String code) {
  final n = _countryNames[code.toUpperCase()];
  if (n == null) return '';
  return L.current == 'en' ? n[1] : n[0];
}

/// Чистит ремарку от флаг-эмодзи и служебных значков (⚡️⭐️🎮 и т.п.),
/// оставляя читаемое имя. Если после чистки пусто — возвращает исходную.
String _cleanRemark(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    // пропускаем региональные индикаторы (флаги) и большинство эмодзи-пиктограмм
    if (r >= 0x1F1E6 && r <= 0x1F1FF) continue; // флаги
    if (r >= 0x1F300 && r <= 0x1FAFF) continue; // разные эмодзи
    if (r >= 0x2600 && r <= 0x27BF) continue; // символы/дингбаты (⚡⭐ и т.п.)
    if (r == 0xFE0F || r == 0x200D) continue; // variation selector / ZWJ
    buf.writeCharCode(r);
  }
  final cleaned = buf.toString().trim();
  return cleaned.isEmpty ? s.trim() : cleaned;
}

/// Извлекает ISO-код страны из флаг-эмодзи в тексте (две региональные буквы
/// U+1F1E6..U+1F1FF идут подряд). Напр. «🇩🇪 Германия» → 'DE'. null, если нет.
String? _countryFromFlagEmoji(String s) {
  final runes = s.runes.toList();
  const base = 0x1F1E6; // regional indicator 'A'
  for (var i = 0; i < runes.length - 1; i++) {
    final a = runes[i], b = runes[i + 1];
    if (a >= base && a <= base + 25 && b >= base && b <= base + 25) {
      return String.fromCharCodes([a - base + 0x41, b - base + 0x41]); // → 'DE'
    }
  }
  return null;
}

/// Грубое определение страны по хосту/ремарке (для UI до реального гео).
/// Сначала пробуем точный IP сервера, затем ключевые слова в хосте и имени.
/// Крупные города и характерные слова → код страны. Нужны там, где в ремарке
/// нет ни названия страны, ни её кода: «Frankfurt», «Ashburn», «Warsaw».
const _cityHints = <String, String>{
  'frankfurt': 'DE', 'berlin': 'DE', 'munich': 'DE', 'nuremberg': 'DE',
  'dusseldorf': 'DE', 'deutschland': 'DE',
  'amsterdam': 'NL', 'rotterdam': 'NL', 'holland': 'NL', 'nether': 'NL',
  'helsinki': 'FI', 'espoo': 'FI',
  'moscow': 'RU', 'spb': 'RU', 'piter': 'RU', 'москва': 'RU', 'питер': 'RU',
  'warsaw': 'PL', 'warszawa': 'PL', 'krakow': 'PL', 'gdansk': 'PL',
  'варшава': 'PL', 'poland': 'PL', 'polska': 'PL',
  'london': 'GB', 'manchester': 'GB', 'britain': 'GB', 'england': 'GB',
  'лондон': 'GB', 'англи': 'GB',
  'paris': 'FR', 'marseille': 'FR', 'париж': 'FR',
  'milan': 'IT', 'rome': 'IT', 'milano': 'IT',
  'madrid': 'ES', 'barcelona': 'ES',
  'stockholm': 'SE', 'oslo': 'NO', 'copenhagen': 'DK', 'reykjavik': 'IS',
  'vienna': 'AT', 'wien': 'AT', 'zurich': 'CH', 'geneva': 'CH',
  'prague': 'CZ', 'praha': 'CZ', 'bratislava': 'SK', 'budapest': 'HU',
  'bucharest': 'RO', 'sofia': 'BG', 'belgrade': 'RS', 'zagreb': 'HR',
  'athens': 'GR', 'lisbon': 'PT', 'dublin': 'IE', 'brussels': 'BE',
  'vilnius': 'LT', 'riga': 'LV', 'tallinn': 'EE', 'kyiv': 'UA', 'kiev': 'UA',
  'chisinau': 'MD', 'minsk': 'BY',
  'istanbul': 'TR', 'ankara': 'TR', 'стамбул': 'TR',
  'dubai': 'AE', 'sharjah': 'AE', 'дубай': 'AE',
  'tokyo': 'JP', 'osaka': 'JP', 'seoul': 'KR', 'taipei': 'TW',
  'singapore': 'SG', 'hongkong': 'HK', 'hong kong': 'HK',
  'mumbai': 'IN', 'delhi': 'IN', 'bangalore': 'IN',
  'sydney': 'AU', 'melbourne': 'AU', 'auckland': 'NZ',
  'toronto': 'CA', 'montreal': 'CA', 'vancouver': 'CA',
  'ashburn': 'US', 'dallas': 'US', 'seattle': 'US', 'chicago': 'US',
  'miami': 'US', 'phoenix': 'US', 'atlanta': 'US', 'york': 'US',
  'america': 'US', 'сша': 'US',
  'saopaulo': 'BR', 'sao paulo': 'BR', 'santiago': 'CL', 'lima': 'PE',
  'almaty': 'KZ', 'astana': 'KZ', 'алматы': 'KZ', 'tashkent': 'UZ',
  'yerevan': 'AM', 'ереван': 'AM', 'tbilisi': 'GE', 'тбилиси': 'GE',
  'telaviv': 'IL', 'tel aviv': 'IL', 'bangkok': 'TH', 'hanoi': 'VN',
  'jakarta': 'ID', 'manila': 'PH', 'johannesburg': 'ZA', 'cairo': 'EG',
};

/// Названия стран → код. Строится ОДИН РАЗ из [_countryNames], поэтому любая
/// страна из таблицы распознаётся автоматически, без отдельного списка.
final Map<String, String> _nameToCode = () {
  final m = <String, String>{};
  for (final e in _countryNames.entries) {
    for (final n in e.value) {
      final key = n.toLowerCase();
      m[key] = e.key;
      // Русские названия склоняются («Германия» → «Германии»): достаточно
      // сравнивать по основе без последних двух букв.
      if (key.length > 5) m[key.substring(0, key.length - 2)] = e.key;
    }
  }
  return m;
}();

/// Определение страны по ремарке и хосту.
///
/// Порядок от самого надёжного к самому приблизительному. Важно, что список
/// стран нигде не дублируется: и названия, и коды берутся из [_countryNames],
/// поэтому новая страна начинает определяться сразу после добавления в таблицу.
String _guessCountry(String name, String host) {
  // 1) Флаг-эмодзи прямо в имени («🇵🇱 Польша») — однозначный признак.
  final fromFlag = _countryFromFlagEmoji(name);
  if (fromFlag != null) return fromFlag;

  // 2) Точный IP нашего сервера.
  final byIp = _knownServerIps[host.trim()];
  if (byIp != null) return byIp;

  final nameL = name.toLowerCase();
  final hostL = host.toLowerCase();

  // 3) Название страны в ремарке («Польша 1», «Poland», «Германии»).
  for (final e in _nameToCode.entries) {
    if (e.key.length >= 4 && nameL.contains(e.key)) return e.value;
  }

  // 4) Код страны ОТДЕЛЬНЫМ словом: «PL», «[PL]», «pl-1», «pl1», «se.node».
  //    Именно отдельным — иначе «de» найдётся в «under», а «in» в «india».
  for (final src in [nameL, hostL]) {
    for (final m in RegExp(r'(?<![a-z0-9])([a-z]{2})(?![a-z])')
        .allMatches(src)) {
      final cc = m.group(1)!.toUpperCase();
      if (_countryNames.containsKey(cc)) return cc;
    }
  }

  // 5) Домен верхнего уровня хоста: «srv.pl», «node.de».
  final tld = RegExp(r'\.([a-z]{2})$').firstMatch(hostL);
  if (tld != null) {
    final cc = tld.group(1)!.toUpperCase();
    if (_countryNames.containsKey(cc)) return cc;
  }

  // 6) Города и характерные слова.
  for (final e in _cityHints.entries) {
    if (hostL.contains(e.key) || nameL.contains(e.key)) return e.value;
  }

  return '';
}
