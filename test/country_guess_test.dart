/// Определение страны по тому, что реально приходит в подписках.
///
/// Имена узлов люди пишут как хотят: с флагом-эмодзи, названием страны на
/// русском, кодом в хосте — или вообще без намёка на географию («YouTube»,
/// «Torrents Free»). Ниже — дословные имена и адреса из настоящих подписок.
///
/// Отдельно закреплено то, чего определять НЕ надо: выдуманный флаг хуже
/// глобуса. Человек по флагу выбирает страну, и ошибка здесь — это не
/// «некрасиво», а «подключился не туда, куда хотел».
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/models/vpn_server.dart';

VpnServer _srv(String name, String host) => VpnServer(
      protocol: VpnProtocol.vless,
      name: name,
      address: host,
      port: 443,
      raw: 'vless://u@$host:443#$name',
    );

void main() {
  group('флаг в имени — самый однозначный признак', () {
    final cases = {
      'Нидерланды🇳🇱': 'NL',
      'Германия🇩🇪': 'DE',
      'Россия🇷🇺': 'RU',
      'Турция🇹🇷': 'TR',
      'Финляндия🇫🇮': 'FI',
      'США+🇺🇸👍': 'US',
    };
    cases.forEach((name, cc) {
      test('$name → $cc', () {
        expect(_srv(name, 'node.example.com').countryCode, cc);
      });
    });
  });

  group('страна по адресу, когда в имени её нет', () {
    final cases = {
      'fi.alpheratzz.org': 'FI',
      'us.fasti.win': 'US',
      'de-3.example.net': 'DE',
      'node.pl': 'PL',
      // Домен Великобритании — .uk, а её код в стандарте GB. Без этой пары
      // все британские узлы оставались без флага.
      'api.ferrin.uk': 'GB',
    };
    cases.forEach((host, cc) {
      test('$host → $cc', () => expect(_srv('Сервер', host).countryCode, cc));
    });
  });

  group('страны нет — и придумывать её нельзя', () {
    for (final (name, host) in [
      ('YouTube🍿', 'yt.noooo.win'),
      ('Torrents Free', 'ndt.alpheratzz.org'),
      ('AI-(Нейросети)🤖', 'ai.noooo.win'),
      ('ICEbreaker🧊', 'ice.noooo.win'),
      ('One-(Первый)✨', 'one.alpheratzz.org'),
    ]) {
      test('$name остаётся без флага', () {
        expect(_srv(name, host).countryCode, '',
            reason: 'выдуманный флаг хуже глобуса: по нему выбирают страну');
      });
    }
  });
}
