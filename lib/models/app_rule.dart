/// Правило маршрутизации для одного приложения на устройстве (per-app routing).
///
/// По APP_LOGIC.md: у каждого приложения может быть свой режим — ИИ выбирает
/// сервер сам, либо пользователь жёстко закрепляет конкретный сервер, либо
/// приложение идёт мимо VPN (direct — напр. банки/госуслуги РФ). Плюс
/// независимый от режима опциональный kill-switch для конкретного приложения.
library;

enum RouteMode {
  ai, // ИИ сам выбирает лучший рабочий сервер
  manualServer, // закреплён конкретный сервер (см. serverId)
  direct; // мимо VPN (bypass)

}

class AppRule {
  final String appId; // package name (Android) / bundle id (iOS)
  final String appName; // отображаемое имя
  RouteMode mode;
  String? serverId; // если mode == manualServer
  bool killSwitch; // блокировать трафик приложения, если VPN упал

  AppRule({
    required this.appId,
    required this.appName,
    this.mode = RouteMode.ai,
    this.serverId,
    this.killSwitch = false,
  });

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'appName': appName,
        'mode': mode.name,
        'serverId': serverId,
        'killSwitch': killSwitch,
      };

  factory AppRule.fromJson(Map<String, dynamic> j) => AppRule(
        appId: j['appId'] as String,
        appName: j['appName'] as String? ?? j['appId'] as String,
        mode: RouteMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => RouteMode.ai,
        ),
        serverId: j['serverId'] as String?,
        killSwitch: j['killSwitch'] as bool? ?? false,
      );
}
