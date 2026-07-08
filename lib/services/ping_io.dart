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

/// Быстрый «прокси»-пинг: время TCP+TLS-хендшейка к Reality-порту сервера.
/// Reality маскируется под TLS www.cloudflare.com, поэтому рукопожатие проходит
/// и мы получаем реальную задержку соединения (RTT+TLS) за ~100-300 мс — быстро
/// и точно, как в Quattro, без медленного полного запроса через ядро.
Future<int> tlsPing(String host, int port) async {
  final sw = Stopwatch()..start();
  SecureSocket? s;
  try {
    s = await SecureSocket.connect(host, port,
        timeout: const Duration(milliseconds: 2500),
        onBadCertificate: (_) => true);
    sw.stop();
    return sw.elapsedMilliseconds;
  } catch (_) {
    // TLS не завершился (напр. Reality отбил как «невалидный клиент») — но TCP
    // мог пройти; откатываемся на TCP-замер, чтобы значение всё же было.
    return tcpPing(host, port);
  } finally {
    s?.destroy();
  }
}
