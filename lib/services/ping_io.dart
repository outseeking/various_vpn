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

/// «Точный» замер: время TCP-подключения ПЛЮС рукопожатия TLS.
///
/// [sni] обязателен для Reality-серверов. Они прикидываются чужим сайтом и
/// отвечают только на рукопожатие с правильным именем; адрес у таких серверов
/// обычно голый IP, и без явного SNI сервер рукопожатие не завершает. Раньше
/// SNI не передавался, рукопожатие падало, и функция МОЛЧА возвращала обычный
/// TCP-замер — в настройках стоял «Точный», а число приходило от быстрого.
///
/// Возвращает -1, если рукопожатие не прошло. Подменять результат TCP-замером
/// здесь нельзя: вызывающий должен знать, каким методом получено число.
Future<int> tlsPing(String host, int port, {String? sni}) async {
  final sw = Stopwatch()..start();
  Socket? raw;
  SecureSocket? sec;
  try {
    raw = await Socket.connect(host, port,
        timeout: const Duration(milliseconds: 2500));
    sec = await SecureSocket.secure(
      raw,
      host: (sni == null || sni.isEmpty) ? host : sni,
      onBadCertificate: (_) => true,
    ).timeout(const Duration(milliseconds: 3000));
    sw.stop();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  } finally {
    try {
      // При успешном secure() сокетом владеет уже SecureSocket — закрываем
      // что-то одно, поэтому оба вызова под защитой.
      sec?.destroy();
      if (sec == null) raw?.destroy();
    } catch (_) {
      // сокет уже закрыт
    }
  }
}
