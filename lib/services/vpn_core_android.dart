/// Android VPN-ядро на пакете flutter_v2ray (Xray внутри).
/// VLESS+Reality (и др. xray-протоколы) — полный туннель, мультихоп-цепочка,
/// per-app split-туннелирование, домашний виджет. Всё это — возможности Android;
/// на iOS используется [IosVpnService] (см. vpn_core_ios.dart).
///
/// Компилируется только под dart:io (mobile/desktop). Пакет flutter_v2ray
/// объявлен только для Android — на iOS его нативной части нет, и этот класс там
/// НЕ создаётся (см. createVpnService в vpn_core_native.dart).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../l10n.dart';
import '../models/app_rule.dart';
import '../models/vpn_server.dart';
import '../models/connection_status.dart';
import 'home_widget_sync.dart';
import 'ping.dart';
import 'vpn_service.dart';
import 'xray_config.dart';

/// Протоколы, которые умеет xray-ядро (flutter_v2ray.parseFromURL).
const _xraySupported = {
  VpnProtocol.vless,
  VpnProtocol.vmess,
  VpnProtocol.trojan,
  VpnProtocol.shadowsocks,
};

class V2RayVpnService implements VpnService {
  final _controller = StreamController<VpnStage>.broadcast();
  final _traffic = StreamController<VpnTraffic>.broadcast();
  late final FlutterV2ray _v2ray = FlutterV2ray(onStatusChanged: _onStatus);
  bool _inited = false;
  VpnStage _stage = VpnStage.disconnected;

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
    _set(switch (status.state.toUpperCase()) {
      'CONNECTED' => VpnStage.connected,
      'CONNECTING' => VpnStage.connecting,
      _ => VpnStage.disconnected,
    });
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
          FlutterV2ray.parseFromURL(entry.raw).getFullConfiguration())
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
      final sockopt = (ss['sockopt'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      sockopt['dialerProxy'] = 'entry';
      ss['sockopt'] = sockopt;
      exitOut['streamSettings'] = ss;

      entryOut['tag'] = 'entry';
      entryOut['mux'] = {'enabled': false};

      exitCfg['outbounds'] = [
        exitOut,
        entryOut,
        {'protocol': 'freedom', 'tag': 'direct'},
      ];
      return jsonEncode(exitCfg);
    } catch (_) {
      return exitBaseConfig; // не собралась цепочка — обычный конфиг выхода
    }
  }

  Future<void> _ensureInit() async {
    if (_inited) return;
    await _v2ray.initializeV2Ray();
    _inited = true;
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
        '${server.protocol.label} пока не поддерживается ядром (нужен sing-box). '
        'Выбери сервер с VLESS+Reality.',
      );
    }
    await _ensureInit();
    _set(VpnStage.connecting);
    final parser = FlutterV2ray.parseFromURL(server.raw);
    // Мультихоп: если задан relay — строим цепочку relay→server, иначе обычный.
    final String rawConfig = (relay != null &&
            _xraySupported.contains(relay.protocol))
        ? _buildChainConfig(relay, server, parser.getFullConfiguration())
        : parser.getFullConfiguration();
    final fullConfig = applyNetOptions(rawConfig, net);

    var pingMs = server.pingMs;
    if (pingMs <= 0) {
      try {
        pingMs = await tlsPing(server.address, server.port)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        pingMs = -1;
      }
      if (pingMs > 0) server.pingMs = pingMs;
    }
    final ping = pingMs > 0 ? ' · $pingMs ms' : '';
    final notifRemark = '${server.flag} ${server.countryName}$ping';

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

  @override
  Future<void> disconnect() async {
    await _v2ray.stopV2Ray();
    _set(VpnStage.disconnected);
  }

  @override
  Future<int> ping(VpnServer server) async {
    if (!_xraySupported.contains(server.protocol)) return -1;
    try {
      await _ensureInit();
      final parser = FlutterV2ray.parseFromURL(server.raw);
      final delay = await _v2ray.getServerDelay(
        config: parser.getFullConfiguration(),
        url: 'https://www.gstatic.com/generate_204',
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
          .getConnectedServerDelay(url: 'https://www.gstatic.com/generate_204')
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
