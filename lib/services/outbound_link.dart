/// Обратная сборка share-ссылки из готового outbound'а.
///
/// Часть подписок отдаёт не список ссылок, а полные конфиги — массивом
/// JSON-объектов (формат v2rayN / Xray) или в схеме sing-box. Внутри приложения
/// сервер везде представлен именно ссылкой: по ней ядро строит конфиг, по ней
/// же определяются транспорт и страна. Поэтому конфиг приводим обратно к
/// ссылке — и дальше он ничем не отличается от импортированного обычным путём.
///
/// Чистая логика без сети и без Flutter — покрывается юнит-тестами.
library;

import 'dart:convert';

/// Собирает share-ссылку из outbound'а формата **Xray** (`protocol`,
/// `settings`, `streamSettings`). Возвращает null, если это служебный outbound
/// (freedom/blackhole/dns) или протокол, который ссылкой не выражается.
String? xrayOutboundToLink(Map ob, {String remark = ''}) {
  final proto = '${ob['protocol'] ?? ''}'.toLowerCase();
  if (proto.isEmpty || _serviceProtocols.contains(proto)) return null;

  final settings = _asMap(ob['settings']);
  final stream = _asMap(ob['streamSettings']);

  // vnext — для vless/vmess, servers — для trojan/shadowsocks/socks.
  final node = _firstMap(settings['vnext']) ?? _firstMap(settings['servers']);
  if (node == null) return null;
  final host = '${node['address'] ?? ''}'.trim();
  if (host.isEmpty) return null;
  final port = _toInt(node['port']) ?? 443;
  final user = _firstMap(node['users']) ?? const {};

  switch (proto) {
    case 'vless':
      final id = '${user['id'] ?? ''}';
      if (id.isEmpty) return null;
      final q = _streamQuery(stream);
      q['encryption'] = '${user['encryption'] ?? 'none'}';
      final flow = '${user['flow'] ?? ''}';
      if (flow.isNotEmpty) q['flow'] = flow;
      return _uri('vless', id, host, port, q, remark);

    case 'vmess':
      return _vmessLink(user, host, port, stream, remark);

    case 'trojan':
      final pass = '${node['password'] ?? user['password'] ?? ''}';
      if (pass.isEmpty) return null;
      return _uri('trojan', pass, host, port, _streamQuery(stream), remark);

    case 'shadowsocks':
      final method = '${node['method'] ?? ''}';
      final pass = '${node['password'] ?? ''}';
      if (method.isEmpty || pass.isEmpty) return null;
      final userinfo = base64Url.encode(utf8.encode('$method:$pass'));
      return 'ss://$userinfo@$host:$port${_fragment(remark)}';
  }
  return null;
}

/// Собирает share-ссылку из outbound'а формата **sing-box** (`type`, `server`,
/// `server_port`, плоские `tls`/`transport`). Схема принципиально другая, но
/// сводится к тем же полям — поэтому нормализуем её и переиспользуем сборку.
String? singboxOutboundToLink(Map ob, {String remark = ''}) {
  final type = '${ob['type'] ?? ''}'.toLowerCase();
  final host = '${ob['server'] ?? ''}'.trim();
  if (host.isEmpty) return null;
  final port = _toInt(ob['server_port']) ?? 443;
  final tag = remark.isNotEmpty ? remark : '${ob['tag'] ?? ''}';

  final q = <String, String>{};
  final tls = _asMap(ob['tls']);
  final reality = _asMap(tls['reality']);
  final utls = _asMap(tls['utls']);
  if (tls['enabled'] == true) {
    q['security'] = reality['enabled'] == true ? 'reality' : 'tls';
    final sni = '${tls['server_name'] ?? ''}';
    if (sni.isNotEmpty) q['sni'] = sni;
    final fp = '${utls['fingerprint'] ?? ''}';
    if (fp.isNotEmpty) q['fp'] = fp;
    final pbk = '${reality['public_key'] ?? ''}';
    if (pbk.isNotEmpty) q['pbk'] = pbk;
    final sid = '${reality['short_id'] ?? ''}';
    if (sid.isNotEmpty) q['sid'] = sid;
    final alpn = _joinList(tls['alpn']);
    if (alpn.isNotEmpty) q['alpn'] = alpn;
  }

  final tr = _asMap(ob['transport']);
  final trType = '${tr['type'] ?? ''}'.toLowerCase();
  q['type'] = trType.isEmpty ? 'tcp' : trType;
  final path = '${tr['path'] ?? ''}';
  if (path.isNotEmpty) q['path'] = path;
  final svc = '${tr['service_name'] ?? ''}';
  if (svc.isNotEmpty) q['serviceName'] = svc;
  final hdrHost = _joinList(_asMap(tr['headers'])['Host']);
  if (hdrHost.isNotEmpty) q['host'] = hdrHost;

  switch (type) {
    case 'vless':
      final id = '${ob['uuid'] ?? ''}';
      if (id.isEmpty) return null;
      q['encryption'] = 'none';
      final flow = '${ob['flow'] ?? ''}';
      if (flow.isNotEmpty) q['flow'] = flow;
      return _uri('vless', id, host, port, q, tag);

    case 'trojan':
      final pass = '${ob['password'] ?? ''}';
      if (pass.isEmpty) return null;
      return _uri('trojan', pass, host, port, q, tag);

    case 'vmess':
      final id = '${ob['uuid'] ?? ''}';
      if (id.isEmpty) return null;
      return _vmessFromParts(
        id: id,
        host: host,
        port: port,
        alterId: _toInt(ob['alter_id']) ?? 0,
        security: '${ob['security'] ?? 'auto'}',
        net: q['type'] ?? 'tcp',
        path: q['path'] ?? '',
        hostHeader: q['host'] ?? '',
        serviceName: q['serviceName'] ?? '',
        tls: q['security'] ?? '',
        sni: q['sni'] ?? '',
        alpn: q['alpn'] ?? '',
        fp: q['fp'] ?? '',
        headerType: '',
        remark: tag,
      );

    case 'shadowsocks':
      final method = '${ob['method'] ?? ''}';
      final pass = '${ob['password'] ?? ''}';
      if (method.isEmpty || pass.isEmpty) return null;
      final userinfo = base64Url.encode(utf8.encode('$method:$pass'));
      return 'ss://$userinfo@$host:$port${_fragment(tag)}';

    // hysteria/hysteria2/tuic/wireguard тоже встречаются, и ссылку для них
    // собрать можно — но наше ядро их не поднимает. Отдаём ссылку, чтобы
    // человек увидел честную причину («протокол не поддерживается»), а не
    // молчаливое исчезновение половины подписки.
    case 'hysteria2':
    case 'hysteria':
      final pass = '${ob['password'] ?? ob['auth_str'] ?? ''}';
      final scheme = type == 'hysteria' ? 'hysteria' : 'hysteria2';
      return _uri(scheme, pass, host, port, q, tag);

    case 'tuic':
      final id = '${ob['uuid'] ?? ''}';
      final pass = '${ob['password'] ?? ''}';
      return _uri('tuic', '$id:$pass', host, port, q, tag);
  }
  return null;
}

// ---- внутреннее ----

const _serviceProtocols = {'freedom', 'blackhole', 'dns', 'loopback'};

/// Query-параметры транспорта по [streamSettings] в формате Xray.
Map<String, String> _streamQuery(Map stream) {
  final q = <String, String>{};
  final net = '${stream['network'] ?? 'tcp'}'.toLowerCase();
  q['type'] = net.isEmpty ? 'tcp' : net;

  final security = '${stream['security'] ?? ''}'.toLowerCase();
  if (security.isNotEmpty && security != 'none') q['security'] = security;

  final tls = _asMap(stream['tlsSettings']);
  final reality = _asMap(stream['realitySettings']);
  final sec = reality.isNotEmpty ? reality : tls;
  final sni = '${sec['serverName'] ?? ''}';
  if (sni.isNotEmpty) q['sni'] = sni;
  final fp = '${sec['fingerprint'] ?? ''}';
  if (fp.isNotEmpty) q['fp'] = fp;
  final alpn = _joinList(sec['alpn']);
  if (alpn.isNotEmpty) q['alpn'] = alpn;
  if (reality.isNotEmpty) {
    final pbk = '${reality['publicKey'] ?? ''}';
    if (pbk.isNotEmpty) q['pbk'] = pbk;
    final sid = '${reality['shortId'] ?? ''}';
    if (sid.isNotEmpty) q['sid'] = sid;
    final spx = '${reality['spiderX'] ?? ''}';
    if (spx.isNotEmpty) q['spx'] = spx;
  }
  if (tls['allowInsecure'] == true) q['allowInsecure'] = '1';

  switch (net) {
    case 'ws':
      final ws = _asMap(stream['wsSettings']);
      _put(q, 'path', ws['path']);
      _put(q, 'host', _asMap(ws['headers'])['Host'] ?? ws['host']);
      break;
    case 'httpupgrade':
      final hu = _asMap(stream['httpupgradeSettings']);
      _put(q, 'path', hu['path']);
      _put(q, 'host', hu['host']);
      break;
    case 'xhttp':
    case 'splithttp':
      final xh = _asMap(stream['xhttpSettings']).isNotEmpty
          ? _asMap(stream['xhttpSettings'])
          : _asMap(stream['splithttpSettings']);
      _put(q, 'path', xh['path']);
      _put(q, 'host', xh['host']);
      _put(q, 'mode', xh['mode']);
      break;
    case 'grpc':
      final g = _asMap(stream['grpcSettings']);
      _put(q, 'serviceName', g['serviceName']);
      _put(q, 'authority', g['authority']);
      if (g['multiMode'] == true) q['mode'] = 'multi';
      break;
    case 'h2':
    case 'http':
      final h = _asMap(stream['httpSettings']);
      _put(q, 'path', h['path']);
      final hh = _joinList(h['host']);
      if (hh.isNotEmpty) q['host'] = hh;
      break;
    case 'kcp':
      final k = _asMap(stream['kcpSettings']);
      _put(q, 'seed', k['seed']);
      _put(q, 'headerType', _asMap(k['header'])['type']);
      break;
    case 'quic':
      final qs = _asMap(stream['quicSettings']);
      _put(q, 'quicSecurity', qs['security']);
      _put(q, 'key', qs['key']);
      _put(q, 'headerType', _asMap(qs['header'])['type']);
      break;
    case 'tcp':
      final t = _asMap(stream['tcpSettings']);
      final header = _asMap(t['header']);
      final ht = '${header['type'] ?? ''}';
      if (ht.isNotEmpty && ht != 'none') {
        q['headerType'] = ht;
        final req = _asMap(header['request']);
        _put(q, 'path', _joinList(req['path']));
        _put(q, 'host', _joinList(_asMap(req['headers'])['Host']));
      }
      break;
  }
  return q;
}

String? _vmessLink(Map user, String host, int port, Map stream, String remark) {
  final id = '${user['id'] ?? ''}';
  if (id.isEmpty) return null;
  final q = _streamQuery(stream);
  return _vmessFromParts(
    id: id,
    host: host,
    port: port,
    alterId: _toInt(user['alterId']) ?? 0,
    security: '${user['security'] ?? 'auto'}',
    net: q['type'] ?? 'tcp',
    path: q['path'] ?? '',
    hostHeader: q['host'] ?? '',
    serviceName: q['serviceName'] ?? '',
    tls: q['security'] ?? '',
    sni: q['sni'] ?? '',
    alpn: q['alpn'] ?? '',
    fp: q['fp'] ?? '',
    headerType: q['headerType'] ?? '',
    remark: remark,
  );
}

/// vmess:// — это base64 от JSON, а не обычный URI (исторический формат v2rayN).
String _vmessFromParts({
  required String id,
  required String host,
  required int port,
  required int alterId,
  required String security,
  required String net,
  required String path,
  required String hostHeader,
  required String serviceName,
  required String tls,
  required String sni,
  required String alpn,
  required String fp,
  required String headerType,
  required String remark,
}) {
  final json = <String, dynamic>{
    'v': '2',
    'ps': remark,
    'add': host,
    'port': '$port',
    'id': id,
    'aid': '$alterId',
    'scy': security.isEmpty ? 'auto' : security,
    'net': net,
    'type': headerType.isEmpty ? 'none' : headerType,
    'host': hostHeader,
    'path': net == 'grpc' ? serviceName : path,
    'tls': tls,
    'sni': sni,
    'alpn': alpn,
    'fp': fp,
  };
  return 'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';
}

String _uri(String scheme, String userinfo, String host, int port,
    Map<String, String> q, String remark) {
  final cleaned = Map<String, String>.from(q)
    ..removeWhere((_, v) => v.isEmpty);
  final query = cleaned.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  // IPv6-адрес в URI обязан быть в квадратных скобках, иначе Uri.parse
  // спотыкается о двоеточия и сервер теряется.
  final h = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
  return '$scheme://${encodeUserInfo(userinfo)}@$h:$port'
      '${query.isEmpty ? '' : '?$query'}${_fragment(remark)}';
}

/// Экранирует в пароле/UUID ТОЛЬКО то, без чего ссылка перестанет разбираться.
///
/// Полное процент-кодирование здесь недопустимо: ядро берёт userInfo из ссылки
/// как есть, без обратного декодирования. Закодированный пароль ушёл бы на
/// сервер закодированным — авторизация молча не проходит, а выглядит это как
/// «сервер не работает». Поэтому трогаем только символы, на которых
/// спотыкается сам разбор URI; в настоящих паролях они практически не
/// встречаются.
String encodeUserInfo(String s) {
  const breaking = {'@', '/', '?', '#', '[', ']', '%', ' '};
  final b = StringBuffer();
  for (final ch in s.split('')) {
    if (breaking.contains(ch)) {
      b.write('%${ch.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

String _fragment(String remark) =>
    remark.isEmpty ? '' : '#${Uri.encodeComponent(remark)}';

void _put(Map<String, String> q, String key, Object? value) {
  final s = '${value ?? ''}';
  if (s.isNotEmpty) q[key] = s;
}

Map _asMap(Object? v) => v is Map ? v : const {};

Map? _firstMap(Object? v) {
  if (v is! List) return null;
  for (final e in v) {
    if (e is Map) return e;
  }
  return null;
}

int? _toInt(Object? v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

/// alpn и Host приходят то строкой, то списком — приводим к «a,b».
String _joinList(Object? v) {
  if (v == null) return '';
  if (v is List) return v.map((e) => '$e').where((e) => e.isNotEmpty).join(',');
  return '$v';
}
