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
  set appRulesJson(String? v) => v == null
      ? _prefs.remove(_kAppRules)
      : _prefs.setString(_kAppRules, v);

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
      if (await f.exists()) return f.readAsString();
    } catch (_) {
      // фоллбэк ниже
    }
    return _prefs.getString(_kConfigsFile);
  }

  Future<File> _configsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_kConfigsFile');
  }

  /// Полный сброс (выход из аккаунта).
  Future<void> clearAll() async {
    await _prefs.clear();
    if (!kIsWeb) {
      try {
        final f = await _configsFile();
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
