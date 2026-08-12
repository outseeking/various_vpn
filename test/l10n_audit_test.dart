/// Аудит переводов: у каждой строки должен быть оба языка, и ни одной лишней.
///
/// Ошибки такого рода не видны при разработке — интерфейс тестируют на русском,
/// а английский всплывает у пользователя пустотой или ключом вместо текста.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/l10n.dart';

void main() {
  test('у каждой строки есть русский и английский', () {
    final broken = <String>[];
    L.debugAll.forEach((key, langs) {
      final ru = (langs['ru'] ?? '').trim();
      final en = (langs['en'] ?? '').trim();
      if (ru.isEmpty) broken.add('$key — нет русского');
      if (en.isEmpty) broken.add('$key — нет английского');
    });
    expect(broken, isEmpty,
        reason: 'строки без перевода:\n${broken.join("\n")}');
  });

  test('английский текст не остался русским', () {
    // Частая оплошность при копировании: заполнили 'en', но текстом с
    // кириллицей. Формально перевод есть, а человек видит русский.
    final cyr = RegExp(r'[А-Яа-яЁё]');
    final broken = <String>[];
    L.debugAll.forEach((key, langs) {
      final en = langs['en'] ?? '';
      if (cyr.hasMatch(en)) broken.add('$key → "$en"');
    });
    expect(broken, isEmpty,
        reason: 'в английском варианте кириллица:\n${broken.join("\n")}');
  });

  test('перевод находится по ключу, а не возвращает сам ключ', () {
    // L.t неизвестного ключа отдаёт сам ключ — на экране это выглядит как
    // «gs_id_hint» вместо текста. Проверяем, что все ключи живые.
    for (final key in L.debugAll.keys) {
      expect(L.t(key), isNot(key), reason: 'ключ $key не разворачивается');
    }
  });
}
