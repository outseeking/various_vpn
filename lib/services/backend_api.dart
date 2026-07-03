/// Клиент нашего бэкенда: загрузка подписки и (позже) привязка аккаунта по
/// Telegram-ID с кодом подтверждения.
///
/// Сейчас рабочий путь — загрузка по subscription-ссылке (агрегатор already в
/// проде: https://nl1.ug-connect.site:8088/sub/{uuid}, см. backend/app/subserver.py).
/// Эндпоинты привязки по коду (requestCode/verifyCode) на бэкенде ещё НЕ
/// реализованы — методы заготовлены, чтобы UI писался под финальный контракт;
/// их добавим в боте/субсервере отдельным шагом.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthResult {
  final bool ok;
  final String? subUrl;
  final String? token;
  final String? error;
  const AuthResult({required this.ok, this.subUrl, this.token, this.error});
}

class BackendApi {
  /// База API привязки аккаунта (TODO: поднять на сервере). Подписку грузим по
  /// абсолютной ссылке, поэтому baseUrl нужен только для auth.
  final String baseUrl;
  BackendApi({this.baseUrl = 'https://nl1.ug-connect.site:8088'});

  /// Загружает БЕСПЛАТНУЮ подписку (общий аккаунт, трафик только Telegram).
  /// Эндпоинт /free отдаёт конфиги общего free-аккаунта. Используется до входа/
  /// оплаты — приложение само ограничивает маршрутизацию только мессенджером.
  Future<String> fetchFreeSubscription() async {
    return fetchSubscription('$baseUrl/free');
  }

  /// Загружает сырое тело подписки по ссылке. Возвращает текст (base64 или
  /// plain-text список ссылок) — дальше его разбирает SubscriptionParser.
  Future<String> fetchSubscription(String subUrl) async {
    final r = await http
        .get(Uri.parse(subUrl), headers: {'User-Agent': 'VariousVPN/0.1'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Подписка недоступна (HTTP ${r.statusCode})');
    }
    return r.body;
  }

  /// Статус подписки по Telegram-ID: {active: bool, until: DateTime?} или null.
  Future<({bool active, DateTime? until})?> subStatus(String tgId) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/me/$tgId'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['found'] != true) return null;
      final until = j['sub_until'] != null
          ? DateTime.tryParse(j['sub_until'] as String)
          : null;
      return (active: j['sub_active'] == true, until: until);
    } catch (_) {
      return null;
    }
  }

  /// Просит бэкенд отправить пользователю код подтверждения в Telegram.
  /// TODO(backend): POST /auth/request_code {tg_id} → бот шлёт 6-значный код.
  Future<bool> requestCode(String tgId) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl/auth/request_code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tg_id': tgId}),
          )
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Проверяет код и возвращает subscription-ссылку + токен устройства.
  /// TODO(backend): POST /auth/verify {tg_id, code} → {sub_url, token}.
  Future<AuthResult> verifyCode(String tgId, String code) async {
    try {
      final r = await http
          .post(
            Uri.parse('$baseUrl/auth/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tg_id': tgId, 'code': code}),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) {
        return AuthResult(ok: false, error: 'Неверный код (HTTP ${r.statusCode})');
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return AuthResult(
        ok: true,
        subUrl: j['sub_url'] as String?,
        token: j['token'] as String?,
      );
    } catch (e) {
      return AuthResult(ok: false, error: '$e');
    }
  }
}
