/// Модель одного VPN-сервера, разобранного из subscription-ссылки.
///
/// Важное: поле [raw] хранит исходную share-ссылку (vless://..., hysteria2://...)
/// в неизменном виде — именно её мы передаём в нативное VPN-ядро (Xray/sing-box),
/// которое само умеет её парсить. Остальные поля разбираем для отображения в UI
/// и для логики выбора сервера (страна, протокол, пинг).
library;

enum VpnProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  hysteria2,
  tuic,
  wireguard,
  unknown;

  /// Узнаваемое имя протокола для UI.
  String get label => switch (this) {
        VpnProtocol.vless => 'VLESS',
        VpnProtocol.vmess => 'VMess',
        VpnProtocol.trojan => 'Trojan',
        VpnProtocol.shadowsocks => 'Shadowsocks',
        VpnProtocol.hysteria2 => 'Hysteria2',
        VpnProtocol.tuic => 'TUIC',
        VpnProtocol.wireguard => 'WireGuard',
        VpnProtocol.unknown => 'Unknown',
      };

  static VpnProtocol fromScheme(String scheme) => switch (scheme.toLowerCase()) {
        'vless' => VpnProtocol.vless,
        'vmess' => VpnProtocol.vmess,
        'trojan' => VpnProtocol.trojan,
        'ss' || 'shadowsocks' => VpnProtocol.shadowsocks,
        'hysteria2' || 'hy2' => VpnProtocol.hysteria2,
        'tuic' => VpnProtocol.tuic,
        'wg' || 'wireguard' => VpnProtocol.wireguard,
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

  /// Пинг в мс. -1 = ещё не измерялся, null невозможен (для простоты UI).
  int pingMs;

  /// Человекочитаемое имя для UI — страна (+ номер, если их несколько в одной).
  /// Проставляется в AppState после импорта (там видны «соседи»). Пусто = берём
  /// [countryName].
  String displayName;

  VpnServer({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
    required this.raw,
    Map<String, String>? params,
    this.pingMs = -1,
    this.displayName = '',
  }) : params = params ?? const {};

  /// Стабильный идентификатор сервера (для правил per-app и хранилища).
  String get id => '${protocol.name}://$address:$port';

  /// Поддерживается ли протокол текущим ядром (Xray/flutter_v2ray). Hysteria2/
  /// TUIC/WireGuard пока нет (нужен sing-box) — такие серверы не выбираем для
  /// автоподключения, чтобы VPN не падал.
  bool get xraySupported => const {
        VpnProtocol.vless,
        VpnProtocol.vmess,
        VpnProtocol.trojan,
        VpnProtocol.shadowsocks,
      }.contains(protocol);

  /// Приоритет транспорта для автоподключения (меньше = лучше). На Android в
  /// flutter_v2ray транспорт httpupgrade падает с "bad file descriptor"
  /// (проблема protect сокета), поэтому его — в конец. Reality самый надёжный.
  int get transportPriority {
    final r = raw.toLowerCase();
    if (r.contains('security=reality')) return 0;
    if (r.contains('type=httpupgrade') || r.contains('type=ws')) return 2;
    return 1; // обычный tcp/grpc/tls
  }

  /// Транспорт из raw-ссылки: reality/tls + tcp/grpc/ws — для показа под сервером.
  /// Напр. «VLESS · Reality · gRPC» или «VLESS · TLS · TCP».
  String get transportLabel {
    final r = raw.toLowerCase();
    final parts = <String>[protocol.label];
    if (r.contains('security=reality')) {
      parts.add('Reality');
    } else if (r.contains('security=tls')) {
      parts.add('TLS');
    }
    if (r.contains('type=grpc')) {
      parts.add('gRPC');
    } else if (r.contains('type=ws')) {
      parts.add('WS');
    } else if (r.contains('type=httpupgrade')) {
      parts.add('HTTPUpgrade');
    } else if (r.contains('type=tcp') || protocol == VpnProtocol.vless) {
      parts.add('TCP');
    }
    return parts.join(' · ');
  }

  /// Имя для показа: страна (или ремарка, если страну не определили).
  String get title => displayName.isNotEmpty ? displayName : countryName;

  /// Название страны на русском (или исходная ремарка, если не определили).
  String get countryName => switch (countryCode) {
        'DE' => 'Германия',
        'NL' => 'Нидерланды',
        'FI' => 'Финляндия',
        'RU' => 'Россия',
        'US' => 'США',
        'GB' => 'Великобритания',
        _ => name,
      };

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

/// Грубое определение страны по хосту/ремарке (для UI до реального гео).
/// Сначала пробуем точный IP сервера, затем ключевые слова в хосте и имени.
String _guessCountry(String name, String host) {
  // 1) точный IP сервера.
  final ip = _knownServerIps[host.trim()];
  if (ip != null) return ip;

  // 2) ключевые слова в ХОСТЕ (он надёжнее ремарки — там реальный поддомен).
  final hostL = host.toLowerCase();
  final nameL = name.toLowerCase();
  const map = {
    'DE': ['de1', 'de2', 'de.', '.de', 'germany', 'герман', 'deutsch', 'frankfurt', 'fra', 'dus'],
    'NL': ['nl1', 'nl.', '.nl', 'netherlan', 'нидерлан', 'amsterdam', 'ams', 'nether'],
    'FI': ['fi1', 'fi.', '.fi', 'finland', 'финлянд', 'helsinki', 'hel'],
    'RU': ['ru1', 'ru2', 'russia', 'росси', 'moscow', 'msk'],
    'US': ['usa', 'united states', 'сша', 'america'],
    'GB': ['uk', 'london', 'britain', 'англи'],
  };
  for (final entry in map.entries) {
    for (final kw in entry.value) {
      if (hostL.contains(kw)) return entry.key;
    }
  }
  // 3) только потом — по ремарке (менее надёжно из-за SNI-камуфляжа).
  for (final entry in map.entries) {
    for (final kw in entry.value) {
      if (nameL.contains(kw)) return entry.key;
    }
  }
  return '';
}
