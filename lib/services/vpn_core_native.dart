/// Нативное VPN-ядро (Android/iOS) на пакете flutter_v2ray (Xray внутри).
/// Фаза 1: VLESS+Reality (и др. xray-протоколы) — полный туннель. Hysteria2/TUIC
/// xray не умеет (нужен sing-box) — для них пока бросаем понятную ошибку.
///
/// Этот файл компилируется ТОЛЬКО под dart:io (mobile/desktop) — на web его
/// заменяет vpn_core_stub.dart (см. vpn_core.dart). Поэтому import flutter_v2ray
/// и dart:io здесь безопасны для web-сборки.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../models/app_rule.dart';
import '../models/vpn_server.dart';
import '../models/connection_status.dart';
import 'vpn_service.dart';
import 'xray_config.dart';

VpnService createVpnService() {
  if (Platform.isAndroid || Platform.isIOS) return V2RayVpnService();
  return StubVpnService(); // desktop без нативной поддержки — заглушка
}

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

      // выходной outbound набирается через входной (dialerProxy=entry).
      // ВАЖНО: сюда должны приходить gRPC-варианты нод (без xtls-flow) — их
      // сервер принимает, и dialerProxy с ними работает. XTLS Vision (flow) НЕ
      // работает через dialerProxy И сервер требует flow — поэтому берём gRPC.
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

    // Заголовок уведомления = флаг + страна + пинг (обновляется при смене
    // сервера, т.к. connect вызывается заново). Пинг добавляем, если измерен.
    final ping = server.pingMs > 0 ? ' · ${server.pingMs} ms' : '';
    final notifRemark = '${server.flag} ${server.countryName}$ping';

    // per-app: реальные package name приложений, исключаемых из VPN
    // (сплит-туннелирование). Приходят из AppState.blockedApps.
    await _v2ray.startV2Ray(
      remark: notifRemark,
      config: fullConfig,
      blockedApps: blockedApps.isEmpty ? null : blockedApps,
      proxyOnly: false,
    );
    // На некоторых прошивках (EMUI/MIUI) системный broadcast со статусом
    // V2RAY_CONNECTION_INFO блокируется в фоне, и onStatusChanged может не
    // прийти, хотя туннель уже поднят (OS VPN = CONNECTED). Поэтому, если через
    // 2.5 с статус всё ещё «подключение», оптимистично считаем подключённым —
    // это отражает реальное состояние ОС и не даёт failover'у рвать туннель.
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
      // Быстрый и надёжный тест-URL (204, глобальный CDN Cloudflare) вместо
      // дефолтного google.com/generate_204 — как в Hiddify/Quattro. Меряется
      // быстро и точно, не зависает на редиректах.
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
  void dispose() {
    _controller.close();
    _traffic.close();
  }
}
