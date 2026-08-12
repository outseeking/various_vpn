/// Резервная копия настроек: перенос на новый телефон и сброс к заводским.
///
/// Главное здесь — не удобство, а безопасность. Файл бэкапа человек пересылает
/// себе в мессенджер, кладёт в облако, иногда отдаёт в поддержку. Если в него
/// попадёт токен доступа, Telegram-ID или персональная ссылка подписки — этим
/// файлом откроют оплаченный доступ с чужого устройства.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:various_vpn/services/storage.dart';

Future<Storage> _fresh(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = Storage.instance;
  await s.resetForTests();
  return s;
}

/// То, что не должно покидать устройство ни при каких условиях.
const _secrets = {
  'auth_token': 'TOKEN-СЕКРЕТ',
  'tg_id': '1658245753',
  'sub_url': 'https://various.example/sub/personal-uuid',
  'personal_sub_url': 'https://various.example/vsub/1658245753',
};

const _settings = {
  'global_mode': 'ai',
  'ping_every_s': 120,
  'dns_block_ads': true,
  'foreign_subs': 'https://other.example/abc',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('в бэкап не попадает ни один секрет', () async {
    final s = await _fresh({..._secrets, ..._settings});
    final dump = s.exportSettings();
    for (final key in _secrets.keys) {
      expect(dump.containsKey(key), isFalse,
          reason: '$key утёк бы в файл, который человек пересылает себе');
    }
    // И на всякий случай — что сами ЗНАЧЕНИЯ не просочились под другим ключом.
    expect(dump.values.map((v) => '$v').join('|'), isNot(contains('СЕКРЕТ')));
    expect(dump.values.map((v) => '$v').join('|'),
        isNot(contains('1658245753')));
  });

  test('обычные настройки в бэкап попадают', () async {
    final s = await _fresh({..._secrets, ..._settings});
    final dump = s.exportSettings();
    expect(dump['global_mode'], 'ai');
    expect(dump['ping_every_s'], 120);
    expect(dump['dns_block_ads'], isTrue);
    expect(dump['foreign_subs'], 'https://other.example/abc');
  });

  test('бэкап переносится на чистое устройство', () async {
    final src = await _fresh({..._secrets, ..._settings});
    final dump = src.exportSettings();

    final dst = await _fresh({});
    final n = dst.importSettings(dump);
    expect(n, dump.length);
    expect(dst.getStr('global_mode'), 'ai');
    expect(dst.getInt('ping_every_s', def: 0), 120);
  });

  test('подсунутый в файл секрет при импорте игнорируется', () async {
    final dst = await _fresh({});
    // Файл бэкапа — обычный текст, его несложно отредактировать. Чужой
    // auth_token из такого файла не должен становиться нашим.
    final n = dst.importSettings({
      'global_mode': 'manual',
      'auth_token': 'ЧУЖОЙ-ТОКЕН',
      'tg_id': '999999999',
    });
    expect(n, 1, reason: 'применяется только настройка, секреты — нет');
    expect(dst.authToken, isNull);
    expect(dst.tgId, isNull);
    expect(dst.getStr('global_mode'), 'manual');
  });

  test('значения неизвестного типа не роняют импорт', () async {
    final dst = await _fresh({});
    final n = dst.importSettings({
      'global_mode': 'ai',
      'странное': {'вложенный': 'объект'},
      'пусто': null,
    });
    expect(n, 1);
  });

  test('сброс настроек не отбирает оплаченный доступ', () async {
    final s = await _fresh({
      ..._secrets,
      ..._settings,
      'onboarding_done': true,
      'terms_accepted': true,
    });
    await s.resetSettings();

    expect(s.authToken, 'TOKEN-СЕКРЕТ', reason: 'доступ терять нельзя');
    expect(s.tgId, '1658245753');
    expect(s.subUrl, isNotNull);
    // А вот настройки — вернуться к заводским.
    expect(s.getStr('global_mode'), isEmpty);
    expect(s.getInt('ping_every_s', def: -1), -1);
    // И повторно проходить онбординг с принятием условий человек не должен.
    expect(s.onboardingDone, isTrue);
  });
}
