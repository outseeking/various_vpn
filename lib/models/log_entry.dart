/// Запись «живого лога» событий: подключения, переключения серверов,
/// маршрутизация, ошибки. По просьбе владельца — видно, что откуда и куда идёт.
library;

enum LogKind {
  info,
  route, // маршрут приложение→сервер
  connect,
  disconnect,
  notice, // то, о чём показываем всплывающее уведомление
  error;

  String get icon => switch (this) {
        LogKind.info => 'ℹ️',
        LogKind.route => '➡️',
        LogKind.connect => '🟢',
        LogKind.disconnect => '⚪',
        LogKind.notice => '🔔',
        LogKind.error => '⚠️',
      };
}

class LogEntry {
  final DateTime time;
  final String text;
  final LogKind kind;
  LogEntry(this.text, this.kind) : time = DateTime.now();

  String get hhmmss {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
