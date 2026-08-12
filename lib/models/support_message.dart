/// Сообщение встроенного чата поддержки. По APP_LOGIC.md §9 — поддержка прямо в
/// приложении (плюс альтернатива: чат в Telegram).
library;

class SupportMessage {
  final String text;
  final bool fromUser; // true — написал пользователь, false — поддержка/бот
  final DateTime time;
  SupportMessage(this.text, {required this.fromUser}) : time = DateTime.now();

  Map<String, dynamic> toJson() =>
      {'text': text, 'fromUser': fromUser, 'time': time.toIso8601String()};

  factory SupportMessage.fromJson(Map<String, dynamic> j) {
    final m =
        SupportMessage(j['text'] as String, fromUser: j['fromUser'] as bool);
    return m;
  }

  String get hhmm {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}
