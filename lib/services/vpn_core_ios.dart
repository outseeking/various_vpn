/// iOS VPN-ядро: Flutter общается с нативным NetworkExtension (Packet Tunnel
/// Provider) через MethodChannel/EventChannel. Конфиг Xray собирается на Dart
/// ([buildXrayConfig]) и обрабатывается тем же [applyNetOptions], что и на
/// Android, поэтому весь роутинг (обход РФ / умный ИИ / AdBlock / фрагментация /
/// бесплатный «только Telegram») сохраняется.
///
/// Ограничения платформы iOS (не наши — системные):
///  • per-app split (blockedApps) в iOS невозможен для обычных приложений —
///    туннель всегда системный; параметр просто игнорируется;
///  • мультихоп (relay) в первой версии iOS не собираем цепочкой — идём одним
///    хопом (сервер-выход), функция деградирует, но подключение работает.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../models/app_rule.dart';
import '../models/connection_status.dart';
import '../models/vpn_server.dart';
import 'ping.dart';
import 'vpn_service.dart';
import 'xray_config.dart';
import 'xray_link.dart';

class IosVpnService implements VpnService {
  static const _m = MethodChannel('various_vpn/ios');
  static const _stageCh = EventChannel('various_vpn/ios/stage');
  static const _trafficCh = EventChannel('various_vpn/ios/traffic');

  final _controller = StreamController<VpnStage>.broadcast();
  final _traffic = StreamController<VpnTraffic>.broadcast();
  VpnStage _stage = VpnStage.disconnected;
  StreamSubscription<dynamic>? _stageSub;
  StreamSubscription<dynamic>? _trafSub;

  IosVpnService() {
    _stageSub = _stageCh.receiveBroadcastStream().listen((e) {
      _set(_mapStage(e?.toString() ?? ''));
    }, onError: (_) {});
    _trafSub = _trafficCh.receiveBroadcastStream().listen((e) {
      if (e is Map && !_traffic.isClosed) {
        int g(String k) => (e[k] as num?)?.toInt() ?? 0;
        _traffic.add(VpnTraffic(
          up: g('up'),
          down: g('down'),
          upSpeed: g('upSpeed'),
          downSpeed: g('downSpeed'),
        ));
      }
    }, onError: (_) {});
  }

  VpnStage get _s => _stage;

  @override
  VpnStage get stage => _s;

  @override
  Stream<VpnStage> get stageStream => _controller.stream;

  @override
  Stream<VpnTraffic> get trafficStream => _traffic.stream;

  void _set(VpnStage s) {
    _stage = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  VpnStage _mapStage(String s) => switch (s.toUpperCase()) {
        'CONNECTED' => VpnStage.connected,
        'CONNECTING' || 'REASSERTING' => VpnStage.connecting,
        'ERROR' => VpnStage.error,
        _ => VpnStage.disconnected,
      };

  @override
  @override
  Future<void> warmUp() async {}

  @override
  Future<bool> requestPermission() async {
    try {
      final ok = await _m.invokeMethod<bool>('prepare');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> connect(VpnServer server,
      {List<AppRule> rules = const [],
      NetOptions net = NetOptions.defaults,
      List<String> blockedApps = const [],
      VpnServer? relay}) async {
    if (!server.xraySupported) {
      _set(VpnStage.error);
      throw UnsupportedError(
        '${server.protocol.label} не поддерживается ядром Xray на iOS. '
        'Выбери сервер VLESS+Reality.',
      );
    }
    _set(VpnStage.connecting);

    // 1) Xray-конфиг из ссылки (чистый Dart) → 2) те же сетевые опции, что и на
    // Android (роутинг сохраняется 1-в-1).
    final base = buildXrayConfigJson(server.raw);
    final fullConfig = applyNetOptions(base, net);

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
    final remark = '${server.flag} ${server.countryName}$ping';

    await _m.invokeMethod('connect', {
      'config': fullConfig,
      'remark': remark,
      'socksPort': kXraySocksPort,
    });
  }

  @override
  Future<void> disconnect() async {
    await _m.invokeMethod('disconnect');
    _set(VpnStage.disconnected);
  }

  @override
  Future<int> ping(VpnServer server, {String? url}) async {
    // Пинг меряем на стороне Dart (TCP/TLS-хендшейк) — не зависит от ядра и
    // работает одинаково на всех платформах.
    try {
      final ms = await tlsPing(server.address, server.port)
          .timeout(const Duration(seconds: 3));
      return ms;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<int> connectedDelay() async {
    try {
      final d = await _m
          .invokeMethod<int>('connectedDelay')
          .timeout(const Duration(seconds: 2));
      return (d ?? -1) < 0 ? -1 : d!;
    } catch (_) {
      return -1;
    }
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    _trafSub?.cancel();
    _controller.close();
    _traffic.close();
  }
}
