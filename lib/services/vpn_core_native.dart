/// Выбор нативного VPN-ядра по ОС (компилируется только под dart:io):
///  • Android → [V2RayVpnService] (flutter_v2ray / Xray) — vpn_core_android.dart;
///  • iOS     → [IosVpnService] (NetworkExtension мост)   — vpn_core_ios.dart;
///  • прочее (desktop) → [StubVpnService] (заглушка).
///
/// Оба платформенных файла — чистый Dart на уровне импорта (flutter_v2ray-код
/// компилируется, но на iOS класс V2RayVpnService не инстанцируется), поэтому
/// сборка каждой платформы берёт только свою реализацию.
library;

import 'dart:io';

import 'vpn_core_android.dart';
import 'vpn_core_ios.dart';
import 'vpn_service.dart';

VpnService createVpnService() {
  if (Platform.isIOS) return IosVpnService();
  if (Platform.isAndroid) return V2RayVpnService();
  return StubVpnService(); // desktop без нативной поддержки — заглушка
}
