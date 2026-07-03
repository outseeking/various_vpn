/// Нативный пинг: время TCP-подключения к host:port (реальная задержка).
library;

import 'dart:io';

Future<int> tcpPing(String host, int port) async {
  // Быстрый одиночный замер времени TCP-хендшейка (как в Happ): короткий
  // таймаут, одна попытка — чтобы список пинговался мгновенно и параллельно.
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port,
        timeout: const Duration(milliseconds: 1800));
    sw.stop();
    socket.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  }
}
