/// Web-заглушка пинга (в браузере нет сырых TCP-сокетов) — имитация.
library;

import 'dart:math';

final _rng = Random();

Future<int> tcpPing(String host, int port) async {
  await Future.delayed(Duration(milliseconds: 150 + _rng.nextInt(250)));
  return 40 + _rng.nextInt(140);
}
