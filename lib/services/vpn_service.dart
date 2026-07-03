/// Абстракция VPN-ядра. Главный экран и логика работают только с этим
/// интерфейсом и НЕ знают, какое ядро под капотом.
///
/// Реализации:
///  - [StubVpnService] — заглушка для Web и ранней разработки (симулирует
///    подключение и пинги, чтобы проверять UI/логику без реального туннеля).
///  - Нативная (flutter_v2ray / sing-box) — добавим на этапе сборки под Android,
///    реализовав тот же интерфейс. Web реальный VPN не умеет в принципе.
library;

import 'dart:async';
import 'dart:math';

import '../models/app_rule.dart';
import '../models/connection_status.dart';
import '../models/vpn_server.dart';
import 'xray_config.dart';

/// Реальная статистика туннеля (байты и скорость), приходит из нативного ядра.
class VpnTraffic {
  final int up; // суммарно отдано, байт
  final int down; // суммарно скачано, байт
  final int upSpeed; // байт/с
  final int downSpeed; // байт/с
  const VpnTraffic(
      {this.up = 0, this.down = 0, this.upSpeed = 0, this.downSpeed = 0});
}

abstract class VpnService {
  VpnStage get stage;
  Stream<VpnStage> get stageStream;

  /// Поток реальной статистики трафика (нативное ядро). Заглушка не шлёт ничего.
  Stream<VpnTraffic> get trafficStream;

  /// Запрос системного разрешения на VPN (Android prepare / iOS NE). На Web и в
  /// заглушке — всегда true.
  Future<bool> requestPermission();

  /// Поднять туннель к [server]. [rules] — per-app маршрутизация (для нативного
  /// ядра; заглушка их игнорирует).
  Future<void> connect(VpnServer server,
      {List<AppRule> rules = const [],
      NetOptions net = NetOptions.defaults,
      List<String> blockedApps = const []});

  Future<void> disconnect();

  /// Замер задержки до сервера, мс. -1 = недоступен.
  Future<int> ping(VpnServer server);

  void dispose();
}

/// Заглушка: имитирует поведение ядра для Web/раннего UI.
class StubVpnService implements VpnService {
  final _controller = StreamController<VpnStage>.broadcast();
  final _traffic = StreamController<VpnTraffic>.broadcast();
  VpnStage _stage = VpnStage.disconnected;
  final _rng = Random();

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

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> connect(VpnServer server,
      {List<AppRule> rules = const [],
      NetOptions net = NetOptions.defaults,
      List<String> blockedApps = const []}) async {
    _set(VpnStage.connecting);
    await Future.delayed(const Duration(milliseconds: 900));
    _set(VpnStage.connected);
  }

  @override
  Future<void> disconnect() async {
    _set(VpnStage.disconnected);
  }

  @override
  Future<int> ping(VpnServer server) async {
    await Future.delayed(Duration(milliseconds: 200 + _rng.nextInt(400)));
    // Стабильно-правдоподобный пинг на основе хоста (чтобы не прыгал хаотично).
    final base = server.address.hashCode.abs() % 180;
    return 25 + base + _rng.nextInt(20);
  }

  @override
  void dispose() {
    _controller.close();
    _traffic.close();
  }
}
