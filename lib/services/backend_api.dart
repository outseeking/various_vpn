/// Клиент нашего бэкенда: загрузка подписки и (позже) привязка аккаунта по
/// Telegram-ID с кодом подтверждения.
///
/// Сейчас рабочий путь — загрузка по subscription-ссылке (агрегатор already в
/// проде: https://nl1.ug-connect.site:8088/sub/{uuid}, см. backend/app/subserver.py).
/// Эндпоинты привязки по коду (requestCode/verifyCode) на бэкенде ещё НЕ
/// реализованы — методы заготовлены, чтобы UI писался под финальный контракт;
/// их добавим в боте/субсервере отдельным шагом.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'device_id.dart';

/// Что подписка рассказывает о себе сама: название сервиса, срок и трафик.
class SubInfo {
  const SubInfo({
    required this.title,
    required this.until,
    required this.used,
    required this.total,
  });

  /// Название сервиса из `profile-title` (пусто, если не прислали).
  final String title;

  /// Дата окончания (null — бессрочная или не сообщается).
  final DateTime? until;

  /// Израсходовано и всего байт. 0 в [total] = лимита нет.
  final int used;
  final int total;

  bool get hasTraffic => total > 0;
}

/// Причина, по которой не удалось скачать чужую подписку. Код разбирается на
/// стороне UI и превращается в человеческий текст с подсказкой, что делать.
class ForeignSubError implements Exception {
  /// bad_url · no_host · tls · not_found · forbidden · server · empty · timeout
  final String code;
  final String? detail;
  const ForeignSubError(this.code, {this.detail});

  @override
  String toString() => 'ForeignSubError($code${detail == null ? '' : ': $detail'})';
}

/// Память о недоступных хостах.
///
/// Панель и узлы иногда лежат (закончилась аренда, профилактика). Без этой
/// памяти КАЖДЫЙ экран заново упирался в сетевой таймаут: цена «от N ₽»,
/// статус подписки, стрик, поддержка — и человек ждал секунды на ровном месте
/// при каждом открытии. Теперь хост, который только что не ответил, некоторое
/// время просто пропускается: запрос отваливается мгновенно, а интерфейс
/// показывает запасные значения.
class HostHealth {
  HostHealth._();

  static final Map<String, DateTime> _downUntil = {};

  /// Сколько не беспокоим упавший хост. Достаточно, чтобы не тормозить
  /// интерфейс, и достаточно мало, чтобы вернувшийся хост быстро подхватился.
  static const _cooldown = Duration(minutes: 3);

  static bool isDown(String host) {
    final until = _downUntil[host];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _downUntil.remove(host);
      return false;
    }
    return true;
  }

  static void markDown(String host) =>
      _downUntil[host] = DateTime.now().add(_cooldown);

  static void markUp(String host) => _downUntil.remove(host);

  /// GET с учётом памяти о падениях. null — хост недоступен или помечен как
  /// упавший; вызывающий обязан иметь запасной вариант.
  static Future<http.Response?> get(Uri url,
      {Duration timeout = const Duration(seconds: 6),
      Map<String, String>? headers}) async {
    final host = url.host;
    if (isDown(host)) return null;
    try {
      final r = await http.get(url, headers: headers).timeout(timeout);
      markUp(host);
      return r;
    } catch (_) {
      markDown(host);
      return null;
    }
  }
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
    final r = await http.get(Uri.parse(subUrl), headers: {
      'User-Agent': 'VariousVPN/0.1'
    }).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Подписка недоступна (HTTP ${r.statusCode})');
    }
    return r.body;
  }

  /// Загружает подписку СТОРОННЕГО сервиса.
  ///
  /// Отличий от [fetchSubscription] два, и оба важны:
  ///
  /// 1. **User-Agent.** Панели подписок (Marzban, Hiddify, 3x-ui, Remnawave)
  ///    отдают РАЗНОЕ содержимое в зависимости от клиента, а незнакомому
  ///    User-Agent часто отвечают 404 или пустотой. Поэтому представляемся по
  ///    очереди как популярные клиенты, пока не придёт непустой ответ. Первым
  ///    идёт v2rayNG — его понимают практически все панели.
  ///
  /// 2. **Понятная ошибка.** Раньше любая неудача превращалась в «проверь
  ///    интернет», и понять, что именно не так, было невозможно. Теперь тип
  ///    сбоя (нет такого адреса / сертификат / код ответа / таймаут) доходит
  ///    до пользователя и до логов.

  /// Список имён короткий намеренно: перебор идёт последовательно, и каждое
  /// лишнее имя — это ещё один запрос с таймаутом. Раньше их было пять по 25
  /// секунд: если панель отвечала медленно, обновление подписки занимало до
  /// двух минут. Первым стоит самый распространённый клиент — обычно всё
  /// заканчивается на нём.
  /// Кем представляемся чужой панели, по убыванию полезности ответа.
  ///
  /// Happ впереди не случайно: панели отдают ему полный конфиг с маршрутизацией,
  /// тогда как v2rayNG у части сервисов получает урезанный ответ или отказ.
  static const _clientAgents = [
    'Happ/2.0',
    'clash-verge/v1.6.0',
    'v2rayNG/1.9.16',
  ];

  /// Скачивает чужую подписку, представляясь разными клиентами.
  ///
  /// [isUsable] решает, годится ли тело: панели отказывают не кодом ошибки, а
  /// подпиской-пустышкой — то один конфиг на 0.0.0.0, то целый JSON с пометкой
  /// «приложение не поддерживается». Отличить их по виду ответа нельзя, зато
  /// видно по результату разбора: пригодных серверов ноль. Проверку передаёт
  /// вызывающий — парсер живёт у него.
  Future<String> fetchForeignSubscription(
    String subUrl, {
    bool Function(String body)? isUsable,
  }) async {
    final uri = Uri.tryParse(subUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ForeignSubError('bad_url');
    }
    Object? lastErr;
    var lastStatus = 0;
    var refused = false;
    for (final ua in _clientAgents) {
      try {
        final r = await http.get(uri, headers: {
          'User-Agent': ua,
          'Accept': '*/*',
          // Отпечаток устройства. Сервисы с привязкой к устройствам без него
          // отдают не отказ, а подписку-ЗАГЛУШКУ: три несуществующих сервера
          // с именами вроде «Установите Happ». Снаружи это неотличимо от
          // «наше приложение не умеет читать подписку».
          ...DeviceId.headers,
        }).timeout(const Duration(seconds: 10));
        lastStatus = r.statusCode;
        if (r.statusCode == 200 && r.body.trim().isNotEmpty) {
          // Отказ под видом подписки — не ответ. Пробуем следующего клиента:
          // тот же адрес другому агенту нередко отдаёт настоящий конфиг.
          if (isUsable != null && !isUsable(r.body)) {
            refused = true;
            continue;
          }
          return r.body;
        }
        // 200 с пустым телом = панель не признала клиента, пробуем следующий.
      } on TimeoutException catch (e) {
        lastErr = e;
      } on SocketException catch (e) {
        // Нет такого хоста или сеть недоступна — перебирать агенты бесполезно.
        throw ForeignSubError('no_host', detail: e.message);
      } on HandshakeException catch (e) {
        // Просроченный/самоподписанный сертификат у чужой панели.
        throw ForeignSubError('tls', detail: e.message);
      } catch (e) {
        lastErr = e;
      }
    }
    // Ни один клиент не получил настоящую подписку, зато получил отказ: у
    // сервиса либо кончился лимит устройств, либо он пускает только свои
    // приложения. Это не «нет связи», и говорить об этом надо иначе.
    if (refused) throw const ForeignSubError('refused');
    if (lastStatus == 404) throw const ForeignSubError('not_found');
    if (lastStatus == 401 || lastStatus == 403) {
      throw const ForeignSubError('forbidden');
    }
    if (lastStatus >= 500) {
      throw ForeignSubError('server', detail: '$lastStatus');
    }
    if (lastStatus == 200) throw const ForeignSubError('empty');
    throw ForeignSubError('timeout', detail: '$lastErr');
  }

  /// Срок подписки из стандартного заголовка `subscription-userinfo`
  /// (`upload=..; download=..; total=..; expire=<unix-ts>`). Так дату окончания
  /// можно показать даже БЕЗ привязки Telegram-ID — по самой ссылке подписки.
  /// Возвращает null, если заголовка нет или expire=0 (бессрочная).
  /// Всё, что подписка рассказывает о себе сама, — из стандартных заголовков.
  ///
  /// Панели отдают их почти все: `subscription-userinfo` (трафик и срок) и
  /// `profile-title` (название сервиса). Показывать это важно: иначе чужая
  /// подписка выглядит в приложении безымянной строкой без срока, тогда как у
  /// нашей видно и дату, и остаток.
  Future<SubInfo?> subInfoFromUrl(String subUrl) async {
    final uri = Uri.tryParse(subUrl);
    if (uri == null || !uri.hasScheme) return null;
    for (final ua in _clientAgents) {
      try {
        final r = await http
            .head(uri, headers: {'User-Agent': ua})
            .timeout(const Duration(seconds: 6));
        final info = r.headers['subscription-userinfo'];
        final rawTitle = r.headers['profile-title'];
        if (info == null && rawTitle == null) continue;

        int? num(String key) {
          final m = RegExp('$key\\s*=\\s*(\\d+)').firstMatch(info ?? '');
          return m == null ? null : int.tryParse(m.group(1)!);
        }

        final exp = num('expire');
        return SubInfo(
          title: _decodeTitle(rawTitle),
          // expire=0 у панелей означает «бессрочно», а не «истекла вчера».
          until: (exp == null || exp == 0)
              ? null
              : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
                  .toLocal(),
          used: (num('upload') ?? 0) + (num('download') ?? 0),
          total: num('total') ?? 0,
        );
      } catch (_) {
        // пробуем следующий User-Agent
      }
    }
    return null;
  }

  /// `profile-title` приходит либо текстом, либо как `base64:<...>`.
  static String _decodeTitle(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (!raw.startsWith('base64:')) return raw.trim();
    try {
      var t = raw.substring(7).trim().replaceAll('-', '+').replaceAll('_', '/');
      t = t.padRight(t.length + (4 - t.length % 4) % 4, '=');
      return utf8.decode(base64.decode(t)).trim();
    } catch (_) {
      return '';
    }
  }

  Future<DateTime?> subExpiryFromUrl(String subUrl) async {
    // Пара попыток и запас по времени: сервер собирает подписку с нескольких
    // нод, а мобильная сеть бывает медленной. Раньше одного короткого таймаута
    // хватало, чтобы импорт падал с «подписка не найдена».
    for (var i = 0; i < 3; i++) {
      try {
        final r = await http.get(Uri.parse(subUrl), headers: {
          'User-Agent': 'VariousVPN/0.1'
        }).timeout(const Duration(seconds: 20));
        final info = r.headers['subscription-userinfo'];
        if (info == null) return null; // ответ есть, но срока в нём нет
        final m = RegExp(r'expire\s*=\s*(\d+)').firstMatch(info);
        final ts = m != null ? int.tryParse(m.group(1)!) : null;
        if (ts == null || ts == 0) return null;
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
            .toLocal();
      } catch (_) {
        if (i < 2) await Future.delayed(const Duration(seconds: 1));
      }
    }
    return null;
  }

  /// Минимальная цена подписки (₽) из панели — чтобы показать «от N ₽» прямо
  /// в приложении и человек не уходил в бота выяснять стоимость.
  /// null — панель недоступна; вызывающий подставит запасное значение.
  Future<int?> minPlanPrice() async {
    try {
      final r = await HostHealth.get(
          Uri.parse('https://panel.ug-connect.site:2053/api/bot-config'),
          timeout: const Duration(seconds: 5));
      if (r == null || r.statusCode != 200) return null;
      final plans = (jsonDecode(r.body) as Map<String, dynamic>)['plans'];
      if (plans is! List || plans.isEmpty) return null;
      final prices = <int>[];
      for (final p in plans) {
        if (p is List && p.length >= 2) {
          final v = int.tryParse('${p[1]}');
          if (v != null && v > 0) prices.add(v);
        }
      }
      if (prices.isEmpty) return null;
      prices.sort();
      return prices.first;
    } catch (_) {
      return null;
    }
  }

  /// Кому принадлежит личная ссылка /sub/{uuid} → Telegram-ID владельца.
  /// Нужно, чтобы при импорте по ссылке приложение само привязало аккаунт:
  /// иначе «огонёк серии», ник и ID в профиле оставались пустыми.
  Future<String?> ownerOfSubUuid(String uuid) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/whoami/$uuid'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['found'] != true) return null;
      final id = j['tg_id'];
      return id == null ? null : '$id';
    } catch (_) {
      return null;
    }
  }

  /// Статус подписки по Telegram-ID: {active: bool, until: DateTime?} или null.
  /// Статус подписки по Telegram-ID.
  ///
  /// Вместе со сроком забираем и имя пользователя: на экране подписки должно
  /// быть видно, на чей аккаунт она оформлена. По голому числовому ID человек
  /// не может понять, свой это аккаунт или чужой.
  Future<({bool active, DateTime? until, String username})?> subStatus(
      String tgId) async {
    try {
      final r = await HostHealth.get(Uri.parse('$baseUrl/me/$tgId'),
          timeout: const Duration(seconds: 6));
      if (r == null || r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['found'] != true) return null;
      final until = j['sub_until'] != null
          ? DateTime.tryParse(j['sub_until'] as String)
          : null;
      return (
        active: j['sub_active'] == true,
        until: until,
        username: '${j['username'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}
