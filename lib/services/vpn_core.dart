/// Выбор реализации VPN-ядра по платформе через conditional import:
///  - web (нет dart.library.io) → vpn_core_stub.dart (StubVpnService);
///  - Android/iOS/desktop → vpn_core_native.dart (V2RayVpnService на flutter_v2ray).
/// Благодаря этому web-сборка НЕ тянет нативный код (VPN-ядро/dart:io).
library;

import 'vpn_service.dart';
import 'vpn_core_stub.dart' if (dart.library.io) 'vpn_core_native.dart' as impl;

/// Создаёт подходящую реализацию VPN-ядра для текущей платформы.
VpnService createVpnService() => impl.createVpnService();
