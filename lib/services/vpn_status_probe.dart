/// Мгновенная проверка «активен ли VPN» на уровне ОС (Android Connectivity
/// Manager). Нужна на старте приложения: плагин сообщает статус только
/// broadcast'ами с задержкой (~5 с на EMUI после удаления из «недавних»), а этот
/// канал отдаёт правду сразу. На web/не-Android — всегда false.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VpnStatusProbe {
  VpnStatusProbe._();

  static const _ch = MethodChannel('various_vpn/status');

  static Future<bool> isSystemVpnActive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final active = await _ch.invokeMethod<bool>('vpnActive');
      return active ?? false;
    } catch (_) {
      return false;
    }
  }
}
