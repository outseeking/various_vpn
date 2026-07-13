/// Авто-VPN в незнакомых сетях. Следит за сменой сети; когда телефон
/// подключается к Wi-Fi, читает его имя (SSID) и, если сеть НЕ в списке
/// доверенных, просит поднять VPN. Дома/на работе (доверенные сети) — не мешает.
///
/// Android требует доступ к геолокации для чтения SSID — без него имя сети
/// приходит пустым, тогда решение не принимаем (не дёргаем пользователя).
/// На web/не-Android — безопасные no-op.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class AutoWifiGuard {
  AutoWifiGuard._();
  static final AutoWifiGuard instance = AutoWifiGuard._();

  final _conn = Connectivity();
  final _info = NetworkInfo();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Вызывается, когда телефон в НЕдоверенной Wi-Fi сети (пора включить VPN).
  void Function()? onUntrustedWifi;

  /// true — доверенная ли сеть с данным SSID (задаёт AppState из своего списка).
  bool Function(String ssid)? isTrusted;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Запустить слежение (идемпотентно). Сразу проверяет текущую сеть.
  void start() {
    if (!_supported || _sub != null) return;
    _sub = _conn.onConnectivityChanged.listen(_onChange);
    _conn.checkConnectivity().then(_onChange);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onChange(List<ConnectivityResult> results) async {
    if (!results.contains(ConnectivityResult.wifi)) return;
    final ssid = await currentSsid();
    if (ssid == null || ssid.isEmpty) return; // не смогли прочитать — не решаем
    if (isTrusted?.call(ssid) ?? false) return; // доверенная сеть — не трогаем
    onUntrustedWifi?.call(); // незнакомая сеть → поднять VPN
  }

  /// Текущее имя Wi-Fi (SSID) без кавычек, либо null, если недоступно.
  /// С таймаутом — на части прошивок вызов может «зависнуть».
  Future<String?> currentSsid() async {
    if (!_supported) return null;
    try {
      var name = await _info
          .getWifiName()
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (name == null) return null;
      name = name.replaceAll('"', '').trim();
      if (name.isEmpty || name == '<unknown ssid>') return null;
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Запросить доступ к геолокации (нужен Android для чтения SSID).
  /// Возвращает true, если доступ есть.
  Future<bool> ensureLocationPermission() async {
    if (!_supported) return false;
    final st = await Permission.locationWhenInUse.request();
    return st.isGranted;
  }
}
