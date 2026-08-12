/// Живое событие iOS: Dynamic Island и карточка на экране блокировки.
///
/// Показывает состояние подключения, не заставляя открывать приложение: на
/// айфонах с «островом» это верхняя строка, на остальных — карточка на
/// заблокированном экране.
///
/// На Android и в вебе — молчаливая заглушка: у них такого механизма нет, а
/// проверять платформу в каждом месте вызова значило бы размазать это условие
/// по всему состоянию.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveActivity {
  LiveActivity._();

  static const _ch = MethodChannel('various_vpn/ios');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Последнее отправленное состояние. Обновлять событие чаще, чем оно
  /// меняется, незачем: система ограничивает частоту, а лишние обращения
  /// стоят батареи. Скорости меняются каждую секунду — их в ключ не берём,
  /// иначе смысл сравнения пропадает.
  static String _last = '';

  /// Отправить состояние. `connected == false` завершает событие — оставлять
  /// на экране блокировки карточку «отключено» нельзя, её пришлось бы убирать
  /// руками.
  static Future<void> push({
    required bool connected,
    required String status,
    required String server,
    required String countryCode,
    required String ping,
    required String up,
    required String down,
    DateTime? since,
  }) async {
    if (!_supported) return;
    final key = '$connected|$status|$server|$countryCode|$ping';
    if (key == _last && !connected) return;
    _last = key;
    try {
      await _ch.invokeMethod<void>('liveActivity', {
        'connected': connected,
        'status': status,
        'server': server,
        'cc': countryCode,
        'ping': ping,
        'up': up,
        'down': down,
        'sinceMs': since?.millisecondsSinceEpoch.toDouble(),
        'appName': 'Various VPN',
      });
    } catch (_) {
      // Разрешения на живые события может не быть — приложение работает и без
      // острова, поэтому молча пропускаем.
    }
  }
}
