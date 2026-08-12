/// Гибридное локальное хранилище: SharedPreferences для мелкого UI-состояния
/// (флаги, выбранный режим, токен) + файл на диске для крупных данных
/// (сырой текст подписки с конфигами). По решению владельца — НЕ синхронизируем
/// между устройствами, всё лежит локально.
///
/// Web-совместимость: path_provider не поддерживает файлы в браузере, поэтому
/// при сбое файловых операций прозрачно падаем обратно в SharedPreferences —
/// чтобы веб-проверка логики работала без изменений в коде выше.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  Storage._();
  static final Storage instance = Storage._();

  late SharedPreferences _prefs;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  /// Забыть уже загруженные настройки и перечитать их заново.
  ///
  /// Нужно тестам: хранилище — синглтон, и без сброса второй сценарий получал
  /// настройки первого. В приложении не используется.
  @visibleForTesting
  Future<void> resetForTests() async {
    _ready = false;
    await init();
  }

  // ---- ключи ----
  static const _kOnboardingDone = 'onboarding_done';
  static const _kSubUrl = 'sub_url';
  static const _kTgId = 'tg_id';
  static const _kAuthToken = 'auth_token';
  static const _kAppRules = 'app_rules_json';
  static const _kGlobalMode = 'global_mode'; // 'ai' | 'manual'
  static const _kManualServerId = 'manual_server_id';
  static const _kConfigsFile = 'configs.txt';

  // ---- универсальные геттеры/сеттеры (для настроек/флагов без отдельных ключей) ----
  bool getBool(String key, {bool def = false}) => _prefs.getBool(key) ?? def;
  void setBool(String key, bool v) => _prefs.setBool(key, v);
  String getStr(String key, {String def = ''}) => _prefs.getString(key) ?? def;
  void setStr(String key, String v) => _prefs.setString(key, v);
  int getInt(String key, {int def = 0}) => _prefs.getInt(key) ?? def;
  void setInt(String key, int v) => _prefs.setInt(key, v);

  // ---- резервная копия настроек ----
  //
  // Снимок ВСЕХ сохранённых настроек: человек меняет телефон или переустанавливает
  // приложение и не собирает заново правила по приложениям, свои серверы и
  // список сайтов в обход. Токен и данные подписки в копию не попадают: файл
  // может уйти в облако или в мессенджер, а это ключ от чужого доступа.
  static const _kSecret = {_kAuthToken, _kTgId, _kSubUrl, 'personal_sub_url'};

  Map<String, Object?> exportSettings() {
    final out = <String, Object?>{};
    for (final k in _prefs.getKeys()) {
      if (_kSecret.contains(k)) continue;
      out[k] = _prefs.get(k);
    }
    return out;
  }

  /// Возвращает число применённых настроек. Значения неизвестных типов
  /// пропускаем молча — файл мог прийти от другой версии приложения.
  int importSettings(Map<String, Object?> data) {
    var n = 0;
    for (final e in data.entries) {
      if (_kSecret.contains(e.key)) continue;
      final v = e.value;
      if (v is bool) {
        _prefs.setBool(e.key, v);
      } else if (v is int) {
        _prefs.setInt(e.key, v);
      } else if (v is double) {
        _prefs.setDouble(e.key, v);
      } else if (v is String) {
        _prefs.setString(e.key, v);
      } else if (v is List) {
        _prefs.setStringList(e.key, v.map((x) => '$x').toList());
      } else {
        continue;
      }
      n++;
    }
    return n;
  }

  /// Сброс к заводским настройкам. Подписку и привязку НЕ трогаем — человек
  /// хочет вернуть настройки к исходным, а не потерять оплаченный доступ.
  Future<void> resetSettings() async {
    for (final k in _prefs.getKeys().toList()) {
      if (_kSecret.contains(k)) continue;
      if (k == _kOnboardingDone || k == 'terms_accepted') continue;
      await _prefs.remove(k);
    }
  }

  // ---- простые флаги/строки ----
  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  set onboardingDone(bool v) => _prefs.setBool(_kOnboardingDone, v);

  String? get subUrl => _prefs.getString(_kSubUrl);
  set subUrl(String? v) =>
      v == null ? _prefs.remove(_kSubUrl) : _prefs.setString(_kSubUrl, v);

  String? get tgId => _prefs.getString(_kTgId);
  set tgId(String? v) =>
      v == null ? _prefs.remove(_kTgId) : _prefs.setString(_kTgId, v);

  String? get authToken => _prefs.getString(_kAuthToken);
  set authToken(String? v) =>
      v == null ? _prefs.remove(_kAuthToken) : _prefs.setString(_kAuthToken, v);

  String get globalMode => _prefs.getString(_kGlobalMode) ?? 'ai';
  set globalMode(String v) => _prefs.setString(_kGlobalMode, v);

  String? get manualServerId => _prefs.getString(_kManualServerId);
  set manualServerId(String? v) => v == null
      ? _prefs.remove(_kManualServerId)
      : _prefs.setString(_kManualServerId, v);

  String? get appRulesJson => _prefs.getString(_kAppRules);
  set appRulesJson(String? v) =>
      v == null ? _prefs.remove(_kAppRules) : _prefs.setString(_kAppRules, v);

  // ---- крупные данные: сырой текст подписки ----
  Future<void> saveConfigsBlob(String blob) async {
    if (kIsWeb) {
      await _prefs.setString(_kConfigsFile, blob);
      return;
    }
    try {
      final f = await _configsFile();
      await f.writeAsString(blob);
    } catch (_) {
      await _prefs.setString(_kConfigsFile, blob); // фоллбэк
    }
  }

  Future<String?> loadConfigsBlob() async {
    if (kIsWeb) return _prefs.getString(_kConfigsFile);
    try {
      final f = await _configsFile();
      // await обязателен: без него ошибка чтения улетела бы мимо catch, и
      // возврата к настройкам (фоллбэк ниже) не случилось бы.
      if (await f.exists()) return await f.readAsString();
    } catch (_) {
      // фоллбэк ниже
    }
    return _prefs.getString(_kConfigsFile);
  }

  Future<File> _configsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_kConfigsFile');
  }

  // ---- крупные данные под своим именем ----
  //
  // Тела чужих подписок — это сотни килобайт готовых конфигов. В настройках им
  // не место: SharedPreferences держит всё в памяти и переписывает файл целиком
  // при каждой правке. Поэтому кладём в отдельные файлы.

  Future<void> saveNamedBlob(String name, String data) async {
    if (kIsWeb) {
      await _prefs.setString('blob_$name', data);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/$name.blob').writeAsString(data);
    } catch (_) {
      await _prefs.setString('blob_$name', data);
    }
  }

  Future<String?> loadNamedBlob(String name) async {
    if (kIsWeb) return _prefs.getString('blob_$name');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$name.blob');
      // await обязателен — иначе сбой чтения обойдёт catch стороной.
      if (await f.exists()) return await f.readAsString();
    } catch (_) {
      // фоллбэк ниже
    }
    return _prefs.getString('blob_$name');
  }

  /// Полный сброс (выход из аккаунта).
  ///
  /// Удаляет и отдельные файлы-хранилища. Без этого выход чистил настройки, а
  /// сохранённые тела подписок оставались на диске — после перезапуска серверы
  /// возвращались, и выход выглядел не сработавшим.
  Future<void> clearAll() async {
    await _prefs.clear();
    if (kIsWeb) return;
    try {
      final f = await _configsFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final e in dir.listSync()) {
        if (e is File && e.path.endsWith('.blob')) e.deleteSync();
      }
    } catch (_) {}
  }
}
