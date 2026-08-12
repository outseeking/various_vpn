/// Распознавание отказа чужой панели.
///
/// Живая проверка sub.pad-service.com показала: панель отвечает кодом 200 и
/// непустым телом даже тогда, когда обслуживать клиента не собирается. Внутри —
/// один конфиг-заглушка с нулевым UUID и адресом 0.0.0.0, в названии текст
/// «Приложение не поддерживается». Приложение принимало это за подписку.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/subscription_parser.dart';

const _refusal =
    'vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1?encryption=none'
    '&type=tcp&security=none#%D0%9F%D1%80%D0%B8%D0%BB%D0%BE%D0%B6%D0%B5%D0%BD'
    '%D0%B8%D0%B5%20%D0%BD%D0%B5%20%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6'
    '%D0%B8%D0%B2%D0%B0%D0%B5%D1%82%D1%81%D1%8F';

void main() {
  test('заглушка-отказ не считается рабочим сервером', () {
    // В base64 — ровно так панель её и присылает.
    final body = base64.encode(utf8.encode(_refusal));
    final decoded = utf8.decode(base64.decode(body));
    expect(decoded, contains('@0.0.0.0:'));

    final servers = SubscriptionParser.parseDetailed(decoded).usable;
    expect(servers, isEmpty,
        reason: 'сервер 0.0.0.0:1 не существует и работать не может');
  });
}
