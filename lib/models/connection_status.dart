/// Состояние VPN-подключения и элементы «живого лога» главного экрана.
library;

enum VpnStage {
  disconnected,
  connecting,
  connected,
  error;

}

/// Одна строка «живого лога»: какое приложение идёт через какой сервер сейчас.
/// Именно это, по APP_LOGIC.md §2, видит пользователь на главном экране.
class RouteEntry {
  final String appName;
  final String serverName;
  final String serverFlag;
  final bool direct; // true = идёт мимо VPN

  const RouteEntry({
    required this.appName,
    required this.serverName,
    this.serverFlag = '🌐',
    this.direct = false,
  });
}
