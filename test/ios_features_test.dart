/// Что из функций Android реально доехало до iOS.
///
/// Проверять это на словах бессмысленно: правила маршрутизации могут молча
/// вырезаться из конфига, и человек увидит лишь то, что VPN работает как-то не
/// так. Поэтому конфиг здесь собирают и смотрят, что внутри.
///
/// Платформа подменяется через debugDefaultTargetPlatformOverride — тот же
/// признак, по которому её определяет и сам код (lib/platform.dart).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:various_vpn/platform.dart';
import 'package:various_vpn/services/xray_config.dart';


/// Минимальный конфиг — тот же приём, что и в остальных тестах ядра: важно не
/// содержимое, а что с ним сделают правила.
String _baseConfig() => jsonEncode({
      'outbounds': [
        {'protocol': 'vless', 'tag': 'proxy', 'streamSettings': {}},
      ],
      'routing': {'rules': []},
    });

void main() {
  // Подмену платформы включает каждый тест сам и сам же снимает. Общий setUp
  // здесь не годится: проверка виджетов следит за отладочными переключателями
  // и считает оставленный включённым признак ошибкой теста.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Признаки платформы: на iOS доступно всё, кроме списка приложений', () {
    // Списка установленных программ система не отдаёт — это ограничение Apple,
    // а не недоделка, и оно должно остаться единственным.
    expect(Caps.perAppRouting, isFalse);

    // Остальное перенесено и обязано быть включено. Если кто-то однажды
    // выключит любое из этого «на всякий случай», тест не даст пройти молча.
    expect(Caps.geoAssets, isTrue,
        reason: 'geo-списки кладутся в ресурсы расширения на сборке');
    expect(Caps.appIconSwitch, isTrue,
        reason: 'запасные значки лежат в бандле, переключает система');
    expect(Caps.vpnTunnel, isTrue);
  });

  test('Правила маршрутизации на iOS остаются в конфиге', () {
    final cfg = applyNetOptions(
      _baseConfig(),
      const NetOptions(
        bypassRu: true,
        adBlock: true,
      ),
    );

    // Раньше на iOS все ссылки на списки вырезались: файлов в бандле не было, а
    // с неизвестным списком Xray не «пропускает правило», а вовсе не стартует.
    // Теперь файлы на месте — значит и правила обязаны остаться.
    expect(cfg, contains('geosite:'),
        reason: 'без geosite перестаёт работать блокировка рекламы и обходы');
  });

}
