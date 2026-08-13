/// Отпечаток устройства для панелей с привязкой к устройствам (HWID).
///
/// Часть сервисов ограничивает подписку числом устройств и узнаёт их по
/// заголовкам запроса. Клиенту, который таких заголовков не шлёт, они отдают не
/// отказ, а ПОДПИСКУ-ЗАГЛУШКУ: три несуществующих сервера с именами вроде
/// «Установите Happ» или «Или включите HWID». Снаружи это выглядит как «наше
/// приложение не умеет читать подписку», хотя читается она прекрасно — просто
/// внутри пусто.
///
/// Отпечаток обязан быть ПОСТОЯННЫМ. Меняющийся при каждом запуске — это новое
/// устройство при каждом запуске: лимит выбирается за несколько дней, и
/// подписка перестаёт работать уже по-настоящему.
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'storage.dart';

class DeviceId {
  DeviceId._();

  static const _key = 'device_hwid';

  /// Постоянный идентификатор этого устройства. Создаётся один раз и живёт в
  /// настройках; переустановка приложения даёт новый — иначе никак, доступа к
  /// настоящему серийному номеру система не даёт ни на одной платформе.
  static String get value {
    final saved = Storage.instance.getStr(_key, def: '');
    if (saved.isNotEmpty) return saved;
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    Storage.instance.setStr(_key, id);
    return id;
  }

  /// Название системы так, как его ждут панели: «ios», «android».
  static String get os {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'desktop',
    };
  }

  static String get osVersion {
    if (kIsWeb) return '1.0';
    try {
      // Строка вида «Version 18.2 (Build 22C152)» — панели ждут просто число.
      final v = Platform.operatingSystemVersion;
      final m = RegExp(r'(\d+(\.\d+)*)').firstMatch(v);
      return m?.group(1) ?? '1.0';
    } catch (_) {
      return '1.0';
    }
  }

  static String get model => kIsWeb ? 'Web' : Platform.operatingSystem;

  /// Заголовки, по которым панель узнаёт устройство и отдаёт настоящие
  /// серверы. Именно этот набор шлют приложения, которые такие сервисы
  /// признают своими.
  static Map<String, String> get headers => {
        'x-hwid': value,
        'x-device-os': os,
        'x-ver-os': osVersion,
        'x-device-model': model,
      };
}
