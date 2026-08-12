/// Android VPN-ядро на пакете flutter_v2ray_client (Xray внутри).
/// VLESS+Reality (и др. xray-протоколы) — полный туннель, мультихоп-цепочка,
/// per-app split-туннелирование, домашний виджет. Всё это — возможности Android;
/// на iOS используется [IosVpnService] (см. vpn_core_ios.dart).
///
/// Компилируется только под dart:io (mobile/desktop). Пакет объявлен только для
/// Android — на iOS его нативной части нет, и этот класс там НЕ создаётся
/// (см. createVpnService в vpn_core_native.dart).
///
/// Почему именно flutter_v2ray_client, а не flutter_v2ray: последний не
/// обновлялся с 2024 года и тащит сборку Xray от марта 2025, в которой ещё нет
/// Hysteria. Здесь ядро свежее (в нём есть proxy/hysteria), лицензия MIT —
/// в отличие от sing-box, который под GPL и потребовал бы открыть исходники
/// всего приложения.
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:path_provider/path_provider.dart' as path;

import '../l10n.dart';
import '../models/app_rule.dart';
import '../models/vpn_server.dart';
import '../models/connection_status.dart';
import 'home_widget_sync.dart';
import 'ping.dart';
import 'vpn_service.dart';
import 'xray_config.dart';

/// Протоколы, которые умеет xray-ядро (V2ray.parseFromURL).
const _xraySupported = {
  VpnProtocol.vless,
  VpnProtocol.vmess,
  VpnProtocol.trojan,
  VpnProtocol.shadowsocks,
  VpnProtocol.hysteria,
  VpnProtocol.hysteria2,
};

/// Обёртка для [compute]: функция должна быть top-level или статической.
/// Собирает финальный Xray-конфиг в фоновом изоляте, чтобы не подвешивать UI.
String _buildConfigInIsolate((String, NetOptions) args) =>
    applyNetOptions(args.$1, args.$2);

class V2RayVpnService implements VpnService {
  final _controller = StreamController<VpnStage>.broadcast();
  final _traffic = StreamController<VpnTraffic>.broadcast();
  late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);
  bool _inited = false;
  VpnStage _stage = VpnStage.disconnected;

  /// Идёт намеренная смена сервера.
  ///
  /// Пока это так, промежуточное «отключено» от ядра игнорируется: startV2Ray
  /// внутри гасит старый outbound и поднимает новый, и статус между ними
  /// ничего не говорит о том, что туннель упал.
  bool _switching = false;
  Timer? _switchGuard;

  /// Что ядро сообщило на самом деле, без подмены на время переключения.
  /// По нему сторожевой таймер решает, чем закончилось переключение.
  VpnStage _reported = VpnStage.disconnected;

  /// Сколько ждём переподключения, прежде чем снова верить статусу «отключено».
  ///
  /// Ядру на смену конфига хватает пары секунд. Двенадцать — с запасом на
  /// медленный сервер, но не настолько долго, чтобы настоящий обрыв остался
  /// незамеченным.
  static const _switchWindow = Duration(seconds: 12);

  void _beginSwitch() {
    _switching = true;
    _switchGuard?.cancel();
    _switchGuard = Timer(_switchWindow, () {
      _switching = false;
      // Окно вышло, а ядро так и не сказало «подключено». Показываем настоящее
      // положение дел: без этого экран навсегда застревал в «Подключение…» —
      // новых статусов ядро уже не пришлёт, а подменённый нами прошлый так и
      // остался бы последним.
      if (_reported != VpnStage.connected) _set(_reported);
    });
  }

  void _endSwitch() {
    _switching = false;
    _switchGuard?.cancel();
    _switchGuard = null;
  }

  @override
  VpnStage get stage => _stage;

  @override
  Stream<VpnStage> get stageStream => _controller.stream;

  @override
  Stream<VpnTraffic> get trafficStream => _traffic.stream;

  void _set(VpnStage s) {
    _stage = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  // Парсит "1.2 MB" → байты (flutter_v2ray отдаёт человекочитаемые строки).
  int _toBytes(String s) {
    final m = RegExp(r'([\d.]+)\s*([KMGT]?)B', caseSensitive: false)
        .firstMatch(s.trim());
    if (m == null) return int.tryParse(s.trim()) ?? 0;
    final v = double.tryParse(m.group(1)!) ?? 0;
    final mult = switch (m.group(2)!.toUpperCase()) {
      'K' => 1024,
      'M' => 1024 * 1024,
      'G' => 1024 * 1024 * 1024,
      'T' => 1024 * 1024 * 1024 * 1024,
      _ => 1,
    };
    return (v * mult).round();
  }

  void _onStatus(V2RayStatus status) {
    final reported = switch (status.state.toUpperCase()) {
      'CONNECTED' => VpnStage.connected,
      'CONNECTING' => VpnStage.connecting,
      _ => VpnStage.disconnected,
    };
    _reported = reported;
    if (reported == VpnStage.connected) _endSwitch();
    // Во время смены сервера «отключено» — это середина перезапуска ядра, а не
    // упавший туннель. Раньше приложение верило ему буквально: кнопка гасла, и
    // человеку приходилось подключаться заново.
    _set(_switching && reported == VpnStage.disconnected
        ? VpnStage.connecting
        : reported);
    if (!_traffic.isClosed) {
      _traffic.add(VpnTraffic(
        up: _toBytes(status.upload.toString()),
        down: _toBytes(status.download.toString()),
        upSpeed: _toBytes(status.uploadSpeed.toString()),
        downSpeed: _toBytes(status.downloadSpeed.toString()),
      ));
    }
  }

  /// Строит конфиг-ЦЕПОЧКУ (мультихоп): трафик идёт [entry] → [exitServer] →
  /// интернет. Достигается через Xray `dialerProxy`: outbound выходной ноды
  /// набирается ЧЕРЕЗ outbound входной. Оба — наши серверы, серверная настройка
  /// не нужна. [exitBaseConfig] — полный конфиг выходного сервера (за основу).
  String _buildChainConfig(
      VpnServer entry, VpnServer exitServer, String exitBaseConfig) {
    try {
      final exitCfg = jsonDecode(exitBaseConfig) as Map<String, dynamic>;
      final entryCfg = jsonDecode(
              V2ray.parseFromURL(entry.raw).getFullConfiguration())
          as Map<String, dynamic>;

      bool isProxy(dynamic o) {
        final p = (o as Map)['protocol'];
        return p != 'freedom' && p != 'blackhole' && p != 'dns';
      }

      final exitOut = (exitCfg['outbounds'] as List).firstWhere(isProxy)
          as Map<String, dynamic>;
      final entryOut = (entryCfg['outbounds'] as List).firstWhere(isProxy)
          as Map<String, dynamic>;

      exitOut['tag'] = 'proxy';
      exitOut['mux'] = {'enabled': false}; // mux ломает dialerProxy-цепочку
      final ss = (exitOut['streamSettings'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final sockopt =
          (ss['sockopt'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      sockopt['dialerProxy'] = 'entry';
      ss['sockopt'] = sockopt;
      exitOut['streamSettings'] = ss;

      entryOut['tag'] = 'entry';
      entryOut['mux'] = {'enabled': false};

      exitCfg['outbounds'] = [
        exitOut,
        entryOut,
        <String, dynamic>{'protocol': 'freedom', 'tag': 'direct'},
      ];
      return jsonEncode(exitCfg);
    } catch (_) {
      return exitBaseConfig; // не собралась цепочка — обычный конфиг выхода
    }
  }

  /// Готовит чужой конфиг к запуску, ничего в нём не выбрасывая.
  ///
  /// Ядру нужны две вещи, иначе оно молча откажется стартовать:
  ///  * inbound `socks` — через него tun2socks заворачивает трафик;
  ///  * рабочий outbound ПЕРВЫМ в списке — оттуда берётся адрес сервера.
  /// Всё остальное — routing, dns, balancers, observatory, policy — остаётся
  /// как есть: это и есть смысл приёма готового конфига.
  ///
  /// null — конфига нет или он непригоден; вызывающий соберёт обычный.
  String? _prepareVendorConfig(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final cfg = jsonDecode(raw) as Map<String, dynamic>;
      final outs = (cfg['outbounds'] as List?)?.toList();
      if (outs == null || outs.isEmpty) return null;

      bool isProxy(dynamic o) {
        if (o is! Map) return false;
        final p = '${o['protocol'] ?? ''}'.toLowerCase();
        return p.isNotEmpty &&
            p != 'freedom' &&
            p != 'blackhole' &&
            p != 'dns' &&
            p != 'loopback';
      }

      final i = outs.indexWhere(isProxy);
      if (i < 0) return null;
      if (i > 0) outs.insert(0, outs.removeAt(i)); // рабочий — первым
      cfg['outbounds'] = outs;

      // socks-inbound: если сервис его не положил, добавляем свой. Порт тот же,
      // что использует ядро по умолчанию.
      final inbounds = (cfg['inbounds'] as List?)?.toList() ?? [];
      final hasSocks = inbounds.any(
          (e) => e is Map && '${e['protocol']}'.toLowerCase() == 'socks');
      if (!hasSocks) {
        inbounds.add({
          'tag': 'socks',
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {'udp': true, 'auth': 'noauth'},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        });
      }
      cfg['inbounds'] = inbounds;
      return jsonEncode(cfg);
    } catch (_) {
      return null; // битый конфиг — не рискуем, идём обычным путём
    }
  }

  Future<void> _ensureInit() async {
    if (_inited) return;
    await _v2ray.initialize();
    _inited = true;
  }

  @override
  Future<void> warmUp() async {
    try {
      await _ensureInit();
    } catch (_) {
      // прогрев не критичен — повторим при подключении
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInit();
    return _v2ray.requestPermission();
  }

  @override
  Future<void> connect(VpnServer server,
      {List<AppRule> rules = const [],
      NetOptions net = NetOptions.defaults,
      List<String> blockedApps = const [],
      VpnServer? relay}) async {
    if (!_xraySupported.contains(server.protocol)) {
      _set(VpnStage.error);
      throw UnsupportedError(
        'Протокол ${server.protocol.label} приложение пока не поддерживает. '
        'Выбери другой сервер из списка.',
      );
    }
    await _ensureInit();
    _set(VpnStage.connecting);
    // Если сервер пришёл готовым конфигом (подписка отдала конфиги, а не
    // ссылки) — берём ЕГО, а не собираем заново по ссылке. Так сохраняются
    // маршрутизация, DNS и балансировщики сервиса: ровно то, что делает Happ.
    // Ссылка переносит только адрес и параметры транспорта, всё остальное из
    // конфига при пересборке терялось.
    final base = _prepareVendorConfig(server.fullConfig) ??
        V2ray.parseFromURL(server.raw).getFullConfiguration();
    // Мультихоп: если задан relay — строим цепочку relay→server, иначе обычный.
    final String rawConfig =
        (relay != null && _xraySupported.contains(relay.protocol))
            ? _buildChainConfig(relay, server, base)
            : base;
    // Сборка конфига разбирает и пересобирает большой JSON (правила
    // маршрутизации: домены ИИ, РФ-списки, реклама, geoip). На UI-потоке это
    // подвешивало интерфейс почти на секунду в момент нажатия — теперь считаем
    // в фоновом изоляте, и кнопка анимируется без рывка.
    final fullConfig = await compute(_buildConfigInIsolate, (rawConfig, net));

    var pingMs = server.pingMs;
    // У Hysteria на этом порту слушает UDP, TCP-хендшейк туда не пройдёт
    // никогда. Замер ради подписи в уведомлении отнял бы три секунды перед
    // КАЖДЫМ подключением и всё равно вернул бы прочерк.
    final tcpReachable = server.protocol != VpnProtocol.hysteria &&
        server.protocol != VpnProtocol.hysteria2;
    if (pingMs <= 0 && tcpReachable) {
      try {
        pingMs = await tlsPing(server.address, server.port)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        pingMs = -1;
      }
      if (pingMs > 0) server.pingMs = pingMs;
    }
    final ping = pingMs > 0 ? ' · $pingMs ms' : '';
    // В бесплатном режиме постоянное уведомление честно говорит, что работает
    // только Telegram. Иначе человек сворачивал приложение, шёл в браузер,
    // видел «нет интернета» и считал, что VPN сломан — это была главная
    // причина удалений. Теперь напоминание всегда перед глазами в шторке.
    final notifRemark = net.telegramOnly
        ? L.t('notif_free')
        : '${server.flag} ${server.countryName}$ping';

    // Диагностика: кладём итоговый конфиг рядом с приложением, во внешнюю
    // папку. Это единственный способ увидеть, ЧТО именно уходит в ядро —
    // иначе о причине «connection closed» можно только гадать. Папка
    // Android/data/<пакет>/files доступна без root и стирается вместе с
    // приложением, секретов наружу не выносит.
    unawaited(_dumpConfig(fullConfig, server));

    _beginSwitch();
    await _v2ray.startV2Ray(
      remark: notifRemark,
      config: fullConfig,
      blockedApps: blockedApps.isEmpty ? null : blockedApps,
      proxyOnly: false,
      notificationDisconnectButtonName: L.t('wdg_disconnect'),
    );
    HomeWidgetSync.saveConnectConfig(
      config: fullConfig,
      remark: notifRemark,
      blockedApps: blockedApps,
    );
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_stage == VpnStage.connecting) _set(VpnStage.connected);
    });
  }

  /// Сохраняет последний конфиг, отданный ядру, — для разбора проблем.
  Future<void> _dumpConfig(String config, VpnServer server) async {
    try {
      final dirs = await path.getExternalStorageDirectories();
      if (dirs == null || dirs.isEmpty) return;
      final dir = dirs.first;
      await File('${dir.path}/last_config.json').writeAsString(config);
      await File('${dir.path}/last_server.txt').writeAsString([
        server.title,
        '${server.address}:${server.port}',
        server.protocol.name,
        server.raw,
      ].join('\n'));
    } catch (_) {
      // диагностика не должна мешать подключению
    }
  }

  @override
  Future<void> disconnect() async {
    _endSwitch();
    await _v2ray.stopV2Ray();
    _set(VpnStage.disconnected);
  }

  @override
  Future<int> ping(VpnServer server, {String? url}) async {
    if (!_xraySupported.contains(server.protocol)) return -1;
    try {
      await _ensureInit();
      // Если у сервера есть готовый конфиг сервиса — меряем по нему: там своя
      // маршрутизация, и задержка получается той же, что при реальной работе.
      final config = _prepareVendorConfig(server.fullConfig) ??
          V2ray.parseFromURL(server.raw).getFullConfiguration();
      final delay = await _v2ray.getServerDelay(
        config: config,
        url: (url == null || url.isEmpty)
            ? kProbeUrl
            : url,
      );
      return delay < 0 ? -1 : delay;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<int> connectedDelay() async {
    try {
      final d = await _v2ray
          .getConnectedServerDelay(url: kProbeUrl)
          .timeout(const Duration(seconds: 2));
      return d < 0 ? -1 : d;
    } catch (_) {
      return -1;
    }
  }

  @override
  void dispose() {
    _controller.close();
    _traffic.close();
  }
}
