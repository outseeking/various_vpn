/// Ссылки, которые встречаются в жизни, а не в документации.
///
/// Жалоба была «большинство ссылок не обрабатывается». Тесты на форматы при
/// этом проходили — значит проверяли они не то, что людям попадается. Разница
/// в мелочах: панели ставят пробелы, ломают регистр схемы, забывают
/// паддинг base64, кладут ссылку в кавычки, добавляют BOM или \r\n.
///
/// Каждая строка ниже — не выдумка, а форма, в которой ссылки реально ходят:
/// из буфера обмена, из QR, из ответа панели. Разбор обязан пережить их все.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/subscription_parser.dart';

const _uuid = '00000000-0000-0000-0000-000000000000';
const _good = 'vless://$_uuid@198.51.100.10:443'
    '?encryption=none&security=reality&sni=example.com&pbk=abc&fp=chrome'
    '&type=tcp#Тест';

/// Сколько РАБОЧИХ серверов вытащили. Именно usable, а не всё подряд:
/// заглушки и мусор в список попадать не должны.
int _count(String body) => SubscriptionParser.parseDetailed(body).usable.length;

void main() {
  group('ссылка приходит не в идеальном виде', () {
    test('лишние пробелы и перевод строки по краям', () {
      expect(_count('   $_good  \n\n'), 1);
    });

    test('переводы строк в стиле Windows', () {
      expect(_count('$_good\r\n$_good\r\n'.replaceAll('#Тест', '#А')), 1,
          reason: 'одинаковые узлы схлопываются, но хотя бы один остаётся');
    });

    test('невидимый знак порядка байтов в начале файла', () {
      // Панели, отдающие файл из Windows, ставят его молча. Раньше он
      // приклеивался к схеме, и строка переставала быть ссылкой.
      expect(_count('﻿$_good'), 1);
    });

    test('схема набрана как попало', () {
      expect(_count(_good.replaceFirst('vless://', 'VLESS://')), 1);
    });

    test('ссылка в кавычках — так её копируют из JSON', () {
      expect(_count('"$_good"'), 1);
    });

    test('среди строк есть комментарии и мусор', () {
      expect(_count('# подписка\n// служебное\n$_good\nпросто текст'), 1);
    });
  });

  group('base64 приходит не в идеальном виде', () {
    String b64(String s) => base64.encode(utf8.encode(s));

    test('обычный', () => expect(_count(b64(_good)), 1));

    test('без паддинга', () {
      expect(_count(b64(_good).replaceAll('=', '')), 1);
    });

    test('разбитый на строки — так его отдают многие панели', () {
      final raw = b64(_good);
      final lines = <String>[];
      for (var i = 0; i < raw.length; i += 64) {
        lines.add(raw.substring(i, (i + 64).clamp(0, raw.length)));
      }
      expect(_count(lines.join('\n')), 1);
    });

    test('в url-безопасном алфавите', () {
      expect(_count(base64Url.encode(utf8.encode(_good))), 1);
    });
  });

  group('то, что сервером быть не должно', () {
    test('пустой ответ', () => expect(_count(''), 0));
    test('страница входа', () => expect(_count('<html><body>hi</body></html>'), 0));

    test('подписка-заглушка: адреса, по которым нельзя соединиться', () {
      // Именно так отвечают панели с привязкой к устройствам. Такой ответ
      // разбирается успешно — и тем опаснее: без проверки адреса человек
      // получил бы три «сервера», ни один из которых не работает.
      const stub = 'vless://$_uuid@0.0.0.0:1?encryption=none&type=tcp#'
          '%D0%A3%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%B8%D1%82%D0%B5';
      expect(_count(stub), 0);
    });
  });
}
