/// Реальный замер пинга до сервера. На мобильных — TCP-connect к host:port
/// (настоящая задержка/доступность), на web — имитация (нет сырых сокетов).
library;

import 'ping_stub.dart' if (dart.library.io) 'ping_io.dart' as impl;

/// Возвращает задержку в мс, или -1 если сервер недоступен.
Future<int> tcpPing(String host, int port) => impl.tcpPing(host, port);

/// Быстрый «прокси»-пинг: TCP+TLS-хендшейк к Reality-порту (реальная задержка).
Future<int> tlsPing(String host, int port) => impl.tlsPing(host, port);
