/// Брендовые звуки подключения/отключения. Тихо игнорирует ошибки (звук —
/// не критичная функция). На web/desktop работает через audioplayers.
library;

import 'package:audioplayers/audioplayers.dart';

class Sound {
  Sound._();
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: 0.6);
    } catch (_) {
      // звук не критичен — молча игнорируем (нет аудио-устройства и т.п.)
    }
  }

  static Future<void> connect() => _play('audio/connect.wav');
  static Future<void> disconnect() => _play('audio/disconnect.wav');
}
