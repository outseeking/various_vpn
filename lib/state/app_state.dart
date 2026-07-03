/// Центральное состояние приложения (ChangeNotifier + provider).
///
/// Связывает хранилище, бэкенд, парсер и VPN-ядро. Экраны читают это состояние
/// и дёргают его методы — вся логика здесь, UI остаётся «тонким».
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../brand.dart';
import '../models/app_rule.dart';
import '../models/connection_status.dart';
import '../models/log_entry.dart';
import '../models/support_message.dart';
import '../l10n.dart';
import '../models/vpn_server.dart';
import '../services/backend_api.dart';
import '../services/ping.dart';
import '../services/sound.dart';
import '../services/storage.dart';
import '../services/subscription_parser.dart';
import '../services/vpn_service.dart';
import '../services/xray_config.dart';

enum GlobalMode { ai, manual }

/// Telegram — отдельная сущность для бесплатного режима «VPN только для ТГ».
const _telegramAppName = 'Telegram';

/// Telegram-ID администраторов (совпадает с ADMIN_IDS на бэкенде). Для показа
/// админ-панели именно владельцу.
const _adminIds = {1658245753};

class AppState extends ChangeNotifier {
  final Storage _storage;
  final BackendApi _api;
  final VpnService vpn;

  AppState({
    required Storage storage,
    required BackendApi api,
    required VpnService vpnService,
  })  : _storage = storage,
        _api = api,
        vpn = vpnService {
    vpn.stageStream.listen((s) {
      final wasConnected = _stage == VpnStage.connected;
      _stage = s;
      final nowConnected = s == VpnStage.connected;
      if (nowConnected && !wasConnected) _startSession();
      if (!nowConnected && wasConnected) _stopSession();
      notifyListeners();
    });
    // Реальная статистика трафика от нативного ядра (на web — не приходит).
    vpn.trafficStream.listen((tr) {
      // Скорость считаем САМИ из прироста суммарных байтов: поля upSpeed/
      // downSpeed на части прошивок (EMUI/Honor) приходят нулевыми, а суммарные
      // байты обновляются исправно. Так скорость всегда живая.
      final now = DateTime.now();
      final dtMs = _lastTrafficAt == null
          ? 0
          : now.difference(_lastTrafficAt!).inMilliseconds;
      if (dtMs >= 300 && bytesDown > 0) {
        final dSec = dtMs / 1000.0;
        final dDown = (tr.down - bytesDown).clamp(0, 1 << 62);
        final dUp = (tr.up - bytesUp).clamp(0, 1 << 62);
        var down = dDown / dSec / 1024;
        var up = dUp / dSec / 1024;
        // если плагин всё же прислал ненулевую скорость — берём максимум
        if (tr.downSpeed > 0) down = tr.downSpeed / 1024;
        if (tr.upSpeed > 0) up = tr.upSpeed / 1024;
        speedDownKbps = down;
        speedUpKbps = up;
      } else if (tr.downSpeed > 0 || tr.upSpeed > 0) {
        speedDownKbps = tr.downSpeed / 1024;
        speedUpKbps = tr.upSpeed / 1024;
      }
      bytesDown = tr.down;
      bytesUp = tr.up;
      _lastTrafficAt = now;
      // Экспоненциальное сглаживание (EMA) — линия графика плавная, без рывков.
      final prev = speedHistory.isEmpty ? speedDownKbps : speedHistory.last;
      final smoothed = prev * 0.55 + speedDownKbps * 0.45;
      speedHistory.add(smoothed);
      if (speedHistory.length > 40) speedHistory.removeAt(0);
      notifyListeners();
    });
    _startAiAutoPing();
  }

  // ---- состояние ----
  List<VpnServer> servers = [];

  /// Пользовательский порядок серверов (список id). Пусто = порядок подписки.
  List<String> _serverOrder = [];

  /// Применяет сохранённый порядок к [servers]: известные — по порядку,
  /// новые (которых нет в порядке) — в конец, сохраняя порядок подписки.
  void _applyServerOrder() {
    if (_serverOrder.isEmpty) return;
    final idx = {for (var i = 0; i < _serverOrder.length; i++) _serverOrder[i]: i};
    servers.sort((a, b) =>
        (idx[a.id] ?? 1 << 30).compareTo(idx[b.id] ?? 1 << 30));
  }

  /// Перетаскивание сервера в списке (пользователь меняет порядок).
  void reorderServers(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final s = servers.removeAt(oldIndex);
    servers.insert(newIndex, s);
    _serverOrder = servers.map((e) => e.id).toList();
    _storage.setStr('server_order', _serverOrder.join('\n'));
    notifyListeners();
  }
  List<AppRule> rules = [];
  GlobalMode mode = GlobalMode.ai;
  String? manualServerId;
  VpnStage _stage = VpnStage.disconnected;
  String? lastError;
  bool busy = false;

  /// Бесплатный режим «только Telegram»: туннелируем ТОЛЬКО трафик Telegram,
  /// всё остальное идёт напрямую. Доступен ДО оплаты/подписки.
  bool telegramOnly = false;

  // ---- настройки пользователя ----
  ThemeMode themeMode = ThemeMode.system;
  bool notificationsEnabled = true;
  bool autoConnect = false;
  bool globeAnimations = true;
  bool killSwitch = false;
  bool bypassRu = true;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  String lang = 'ru'; // 'ru' | 'en'

  // ---- сплит-туннелирование (per-app, в стиле Quattro) ----
  bool splitEnabled = false; // «Включить туннелирование трафика»
  bool splitThroughVpn = false; // true=«Через VPN» (выбранные→VPN, остальные напрямую)
  //                                false=«В обход VPN» (выбранные напрямую, остальные→VPN)
  Set<String> splitApps = {}; // выбранные package name
  Set<String> allPackages = {}; // все установленные (для режима «Через VPN»)
  Set<String> splitUrls = {}; // домены в обход VPN (URL-split, идут напрямую)

  void addSplitUrl(String raw) {
    final d = _normalizeDomain(raw);
    if (d.isEmpty) return;
    splitUrls.add(d);
    _storage.setStr('split_urls', splitUrls.join('\n'));
    notifyListeners();
    _reconnectIfActive();
  }

  void removeSplitUrl(String d) {
    splitUrls.remove(d);
    _storage.setStr('split_urls', splitUrls.join('\n'));
    notifyListeners();
    _reconnectIfActive();
  }

  void toggleSplitUrl(String d, bool on) =>
      on ? addSplitUrl(d) : removeSplitUrl(d);

  /// Приводит ввод (https://site.com/path) к домену (site.com).
  String _normalizeDomain(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    s = s.replaceFirst(RegExp(r'^www\.'), '');
    s = s.split('/').first.split('?').first.split(':').first;
    return s;
  }

  void setSplitEnabled(bool v) {
    splitEnabled = v;
    _storage.setBool('split_enabled', v);
    notifyListeners();
    _reconnectIfActive();
  }

  void setSplitThroughVpn(bool v) {
    splitThroughVpn = v;
    _storage.setBool('split_through', v);
    notifyListeners();
    _reconnectIfActive();
  }

  void toggleSplitApp(String pkg, bool on) {
    if (on) {
      splitApps.add(pkg);
    } else {
      splitApps.remove(pkg);
    }
    _storage.setStr('split_apps', splitApps.join('\n'));
    notifyListeners();
    _reconnectIfActive();
  }

  /// Список приложений, исключаемых из VPN (blockedApps для flutter_v2ray).
  /// «В обход VPN»: выбранные идут напрямую → blocked = выбранные.
  /// «Через VPN»: только выбранные в туннеле → blocked = все, кроме выбранных.
  List<String> get blockedApps {
    if (!splitEnabled || splitApps.isEmpty) return const [];
    if (splitThroughVpn) {
      return allPackages.where((p) => !splitApps.contains(p)).toList();
    }
    return splitApps.toList();
  }

  // ---- сетевые настройки (идут в Xray-конфиг) ----
  IpStrategy ipStrategy = IpStrategy.auto;
  String customDns = ''; // пусто = дефолтный DNS сервера
  bool fragment = false; // фрагментация TLS против DPI

  /// Собранные сетевые опции для передачи в ядро при connect.
  NetOptions get net => NetOptions(
        dns: customDns.trim().isEmpty
            ? const []
            : customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        bypassRu: bypassRu,
        ipStrategy: ipStrategy,
        fragment: fragment,
        directDomains: splitUrls.toList(),
      );

  void setIpStrategy(IpStrategy v) {
    ipStrategy = v;
    _storage.setStr('ip_strategy', v.name);
    notifyListeners();
    _reconnectIfActive();
  }

  void setCustomDns(String v) {
    customDns = v.trim();
    _storage.setStr('custom_dns', customDns);
    notifyListeners();
    _reconnectIfActive();
  }

  void setFragment(bool v) {
    fragment = v;
    _storage.setBool('fragment', v);
    notifyListeners();
    _reconnectIfActive();
  }

  void _reconnectIfActive() {
    if (isConnected) _reconnectTo();
  }

  // ---- логи и всплывающие уведомления ----
  final List<LogEntry> logs = [];
  /// Транзиентное уведомление для всплывашки (SnackBar). UI слушает и сбрасывает.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  VpnStage get stage => _stage;
  bool get isConnected => _stage == VpnStage.connected;
  bool get hasServers => servers.isNotEmpty;

  /// Загрузка сохранённого состояния при старте.
  Future<void> bootstrap() async {
    await _storage.init();
    mode = _storage.globalMode == 'manual' ? GlobalMode.manual : GlobalMode.ai;
    manualServerId = _storage.manualServerId;
    themeMode = _themeFromStr(_storage.getStr('theme_mode', def: 'system'));
    notificationsEnabled = _storage.getBool('notifications', def: true);
    autoConnect = _storage.getBool('auto_connect', def: false);
    // Тумблер анимаций убран из настроек — анимации глобуса всегда включены
    // (иначе у тех, кто раньше выключил, звёзды/падающие звёзды не работали бы).
    globeAnimations = true;
    _storage.setBool('globe_anim', true);
    killSwitch = _storage.getBool('kill_switch', def: false);
    bypassRu = _storage.getBool('bypass_ru', def: true);
    soundEnabled = _storage.getBool('sound', def: true);
    vibrationEnabled = _storage.getBool('vibration', def: true);
    ipStrategy = IpStrategy.values.firstWhere(
      (e) => e.name == _storage.getStr('ip_strategy', def: 'auto'),
      orElse: () => IpStrategy.auto,
    );
    customDns = _storage.getStr('custom_dns', def: '');
    fragment = _storage.getBool('fragment', def: false);
    splitEnabled = _storage.getBool('split_enabled', def: false);
    splitThroughVpn = _storage.getBool('split_through', def: false);
    final splitRaw = _storage.getStr('split_apps', def: '');
    splitApps = splitRaw.isEmpty ? {} : splitRaw.split('\n').toSet();
    final orderRaw = _storage.getStr('server_order', def: '');
    _serverOrder = orderRaw.isEmpty ? [] : orderRaw.split('\n');
    final urlsRaw = _storage.getStr('split_urls', def: '');
    splitUrls = urlsRaw.isEmpty ? {} : urlsRaw.split('\n').toSet();
    // Язык: сохранённый или по локали устройства (en → en, иначе ru).
    final savedLang = _storage.getStr('lang', def: '');
    lang = savedLang.isNotEmpty
        ? savedLang
        : (PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'ru');
    L.current = lang;
    final favRaw = _storage.getStr('favorites', def: '');
    favorites = favRaw.isEmpty ? {} : favRaw.split('\n').toSet();
    final statsRaw = _storage.getStr('alltime_stats', def: '');
    if (statsRaw.isNotEmpty) {
      try {
        _allTime = jsonDecode(statsRaw) as Map<String, dynamic>;
        _allTime['countries'] ??= {};
        _allTime['days'] ??= {};
      } catch (_) {}
    }
    _loadRules();
    final blob = await _storage.loadConfigsBlob();
    if (blob != null && blob.isNotEmpty) {
      servers = SubscriptionParser.parseContent(blob);
      _assignDisplayNames();
    }
    notifyListeners();
    // Статус подписки — в фоне (не блокируем старт UI).
    refreshSubStatus();
    // Сразу измерим пинги (в фоне, TCP) — чтобы значения были видны при входе,
    // а не появлялись только через 30 сек на первом авто-тике.
    if (servers.isNotEmpty) _pingAllSilent(background: true);
    // Источник серверов — админ-панель. Если ссылка не привязана, привязываем
    // панельную (/vsub) и подтягиваем серверы в фоне: добавил сервер в панели →
    // он появляется в приложении и на глобусе.
    _syncFromPanel();
  }

  Future<void> _syncFromPanel() async {
    // Панель — единственный источник серверов. Всегда переключаем ссылку на неё
    // (перетираем старые импортированные URL), чтобы вкл/выкл сервера в панели
    // сразу отражались в приложении.
    _storage.subUrl = Brand.panelSub;
    const url = Brand.panelSub;
    try {
      final raw = await _api.fetchSubscription(url);
      final parsed = SubscriptionParser.parseContent(raw);
      if (parsed.isNotEmpty) {
        servers = parsed;
        _assignDisplayNames();
        await _storage.saveConfigsBlob(raw);
        notifyListeners();
        _pingAllSilent(background: true);
      }
    } catch (_) {
      // панель недоступна — работаем на сохранённых серверах
    }
  }

  // ---- логи/уведомления ----

  void _log(String text, [LogKind kind = LogKind.info]) {
    logs.insert(0, LogEntry(text, kind));
    if (logs.length > 300) logs.removeRange(300, logs.length);
  }

  /// Записать в лог и (если включены уведомления) показать всплывашку.
  void _notify(String text) {
    _log(text, LogKind.notice);
    if (notificationsEnabled) notice.value = text;
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ---- статистика текущей сессии ----
  // Скорости пока имитируются (реальные подключим из нативного ядра —
  // V2RayStatus.upload/downloadSpeed). Структура готова под реальные данные.
  DateTime? _sessionStart;
  Timer? _sessionTimer;
  int bytesDown = 0; // суммарно за сессию
  int bytesUp = 0;
  double speedDownKbps = 0;
  double speedUpKbps = 0;
  DateTime? _lastTrafficAt; // для расчёта скорости из прироста байтов
  final List<double> speedHistory = []; // последние ~30 точек (КБ/с, down)

  Duration get sessionDuration =>
      _sessionStart == null ? Duration.zero : DateTime.now().difference(_sessionStart!);

  void _startSession() {
    _sessionStart = DateTime.now();
    bytesDown = 0;
    bytesUp = 0;
    speedDownKbps = 0;
    speedUpKbps = 0;
    _lastTrafficAt = null;
    _sessionCountry = activeServer?.countryName ?? '';
    speedHistory.clear();
    if (vibrationEnabled) HapticFeedback.mediumImpact();
    if (soundEnabled) Sound.connect();
    _sessionTimer?.cancel();
    // Таймер только для обновления времени сессии. Трафик/скорость — реальные,
    // приходят из vpn.trafficStream (на web их нет, поэтому график пустой).
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    _startWatchdog();
  }

  // ---- watchdog: авто-восстановление «мёртвого» туннеля ----
  // На EMUI/Honor система усыпляет VPN-сервис: иконка «подключено» горит, а
  // трафика нет. Периодически проверяем связь ЧЕРЕЗ туннель (getServerDelay);
  // если сервер не отвечает несколько раз подряд — переподнимаем ядро на месте
  // (restartCoreInPlace), не рвя сервис и уведомление.
  Timer? _watchdogTimer;
  int _healthFails = 0;

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _healthFails = 0;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!isConnected || _switching) return;
      // HTTP-проба ЧЕРЕЗ туннель (наш трафик идёт через VPN). Живой туннель —
      // быстрый ответ; мёртвый (сервис усыплён на EMUI) — таймаут.
      final ok = await _tunnelAlive();
      if (ok) {
        _healthFails = 0;
        return;
      }
      _healthFails++;
      if (_healthFails >= 2) {
        // ~50 с подряд без связи через туннель → туннель мёртв, оживляем.
        _healthFails = 0;
        _log('VPN не отвечает — переподключаюсь автоматически', LogKind.notice);
        await _reconnectTo();
      }
    });
  }

  Future<bool> _tunnelAlive() async {
    try {
      final r = await http
          .get(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 6));
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _healthFails = 0;
  }

  void _stopSession() {
    // Уведомление: страна + сколько времени пользовались сервером.
    final dur = sessionDuration;
    if (_sessionCountry.isNotEmpty) {
      final h = dur.inHours, m = dur.inMinutes % 60, s = dur.inSeconds % 60;
      final t = h > 0 ? '$h ч $m мин' : (m > 0 ? '$m мин $s с' : '$s с');
      _notify('Отключено от: $_sessionCountry · время: $t');
    }
    _accumulateStats(); // копим в статистику за всё время
    _stopWatchdog();
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _sessionStart = null;
    speedDownKbps = 0;
    speedUpKbps = 0;
    if (vibrationEnabled) HapticFeedback.lightImpact();
    if (soundEnabled) Sound.disconnect();
    notifyListeners();
  }

  // ---- статистика за всё время (накопительная, переживает перезапуск) ----
  // {down,up: int; countries: {имя: int}; days: {yyyy-mm-dd: int}}
  Map<String, dynamic> _allTime = {'down': 0, 'up': 0, 'countries': {}, 'days': {}};
  String _sessionCountry = '';

  int get allTimeDown => (_allTime['down'] as num).toInt();
  int get allTimeUp => (_allTime['up'] as num).toInt();

  /// Топ стран по трафику: список (страна, байты), по убыванию.
  List<MapEntry<String, int>> get topCountries {
    final m = (_allTime['countries'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()));
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Трафик за последние 7 дней: список (день, байты), от старого к новому.
  List<MapEntry<String, int>> get last7Days {
    final days = (_allTime['days'] as Map);
    final out = <MapEntry<String, int>>[];
    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      out.add(MapEntry('${d.day}.${d.month}', ((days[key] ?? 0) as num).toInt()));
    }
    return out;
  }

  void _accumulateStats() {
    _allTime['down'] = allTimeDown + bytesDown;
    _allTime['up'] = allTimeUp + bytesUp;
    if (_sessionCountry.isNotEmpty) {
      final c = (_allTime['countries'] as Map);
      c[_sessionCountry] = ((c[_sessionCountry] ?? 0) as num).toInt() + bytesDown;
    }
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final days = (_allTime['days'] as Map);
    days[key] = ((days[key] ?? 0) as num).toInt() + bytesDown;
    _storage.setStr('alltime_stats', jsonEncode(_allTime));
  }

  // ---- избранные серверы ----
  Set<String> favorites = {};

  bool isFavorite(String id) => favorites.contains(id);

  void toggleFavorite(String id) {
    if (!favorites.add(id)) favorites.remove(id);
    _storage.setStr('favorites', favorites.join('\n'));
    notifyListeners();
  }

  // ---- поддержка (встроенный чат) ----

  final List<SupportMessage> supportChat = [];

  /// Отправить сообщение в поддержку → в админ-панель (раздел «Поддержка»).
  /// Ответ админа приходит и в Telegram, и в приложение (см. loadSupport).
  Future<void> sendSupport(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    supportChat.add(SupportMessage(t, fromUser: true));
    notifyListeners();
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) {
      supportChat.add(SupportMessage(
        'Чтобы мы могли ответить прямо в приложении, привяжи Telegram в профиле. '
        'Срочное — в Telegram-поддержке (значок вверху).',
        fromUser: false,
      ));
      notifyListeners();
      return;
    }
    try {
      await http.post(
        Uri.parse('${Brand.panelBase}/api/app/support'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tg_id': tg, 'text': t}),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      supportChat.add(SupportMessage(
        'Не удалось отправить сейчас — проверь интернет и попробуй ещё раз.',
        fromUser: false,
      ));
      notifyListeners();
    }
  }

  /// Подтягивает переписку поддержки из панели (ответы админа).
  Future<void> loadSupport() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse('${Brand.panelBase}/api/app/support?tg_id=$tg'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final list = (jsonDecode(r.body)['messages'] as List?) ?? [];
      supportChat
        ..clear()
        ..addAll(list.map((m) => SupportMessage(
              (m['body'] ?? '').toString(),
              fromUser: m['from_admin'] != true,
            )));
      notifyListeners();
    } catch (_) {}
  }

  // ---- админ ----

  /// Сохранить Telegram-ID локально (используется при входе; от него зависит
  /// показ админ-панели). При полноценном входе ID подтверждается кодом.
  void setTgId(String id) {
    final v = id.trim();
    _storage.tgId = v.isEmpty ? null : v;
    notifyListeners();
  }

  /// Является ли текущий пользователь администратором (по Telegram-ID из бота).
  bool get isAdmin {
    final id = int.tryParse(_storage.tgId ?? '');
    return id != null && _adminIds.contains(id);
  }

  // ---- статус подписки (для карточки на главной, как в Quattro) ----
  bool subActive = false;
  DateTime? subUntil;
  bool subLoaded = false;

  /// Подтягивает статус подписки с бэкенда по сохранённому Telegram-ID.
  Future<void> refreshSubStatus() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) {
      subLoaded = true;
      notifyListeners();
      return;
    }
    final st = await _api.subStatus(tg);
    if (st != null) {
      subActive = st.active;
      subUntil = st.until;
    }
    subLoaded = true;
    notifyListeners();
  }

  /// Компактная строка трафика для нижней панели главного экрана (что→куда),
  /// чтобы не открывать «Логи». Пусто, если не подключены.
  List<String> get trafficLines {
    return liveRoutes
        .map((r) => '${r.serverFlag} ${r.appName} → '
            '${r.direct ? "напрямую" : r.serverName}')
        .toList();
  }

  // ---- импорт подписки ----

  /// Умный импорт: сам определяет, что вставили — ссылку подписки (http/https,
  /// одной строкой) или сам текст конфигов (vless://…, base64). Так
  /// пользователю не нужно гадать, какую кнопку нажать.
  Future<bool> importSmart(String input) {
    final t = input.trim();
    final lower = t.toLowerCase(); // схема URL регистронезависима (Https:// тоже)
    final isUrl =
        (lower.startsWith('http://') || lower.startsWith('https://')) &&
            !t.contains('\n');
    return isUrl ? importFromUrl(t) : importFromContent(t);
  }

  /// Импорт по subscription-ссылке (грузим с бэкенда, парсим, сохраняем).
  Future<bool> importFromUrl(String url) async {
    _setBusy(true);
    try {
      final raw = await _api.fetchSubscription(url.trim());
      final parsed = SubscriptionParser.parseContent(raw);
      if (parsed.isEmpty) {
        lastError = 'В подписке не найдено ни одного сервера';
        return false;
      }
      servers = parsed;
      _assignDisplayNames();
      _storage.subUrl = url.trim();
      await _storage.saveConfigsBlob(raw);
      _log('Импортирована подписка: ${servers.length} серверов', LogKind.info);
      lastError = null;
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Обновление уже сохранённой подписки (перекачивает список серверов
  /// с того же URL, которым пользователь подключался изначально).
  Future<bool> refreshSubscription() async {
    final url = _storage.subUrl;
    if (url == null || url.isEmpty) {
      _notify('Подписка не привязана к ссылке — импортируй заново');
      return false;
    }
    final ok = await importFromUrl(url);
    _notify(ok ? 'Подписка обновлена' : 'Не удалось обновить подписку');
    return ok;
  }

  /// Импорт из вставленного текста (одна ссылка или base64-подписка).
  Future<bool> importFromContent(String content) async {
    _setBusy(true);
    try {
      final parsed = SubscriptionParser.parseContent(content);
      if (parsed.isEmpty) {
        lastError = 'Не удалось распознать ни одного сервера';
        return false;
      }
      servers = parsed;
      _assignDisplayNames();
      await _storage.saveConfigsBlob(content);
      _log('Импортировано серверов: ${servers.length}', LogKind.info);
      lastError = null;
      return true;
    } finally {
      _setBusy(false);
    }
  }

  /// Проставляет человекочитаемые имена-страны. Если в одной стране несколько
  /// серверов — добавляет номер («Германия 1», «Германия 2»).
  void _assignDisplayNames() {
    // Группируем по КОДУ страны (а не по ремарке). Несколько серверов одной
    // страны → «Германия 1», «Германия 2». Страну не определили → «Сервер N».
    final byCode = <String, List<VpnServer>>{};
    for (final s in servers) {
      byCode.putIfAbsent(s.countryCode, () => []).add(s);
    }
    var unknownN = 0;
    for (final entry in byCode.entries) {
      final group = entry.value;
      if (entry.key.isEmpty) {
        // без страны — чистое «Сервер N» вместо длинной ремарки.
        for (final s in group) {
          unknownN++;
          s.displayName = 'Сервер $unknownN';
        }
        continue;
      }
      final country = group.first.countryName;
      if (group.length == 1) {
        group.first.displayName = country;
      } else {
        for (var i = 0; i < group.length; i++) {
          group[i].displayName = '$country ${i + 1}';
        }
      }
    }
    // после присвоения имён — применяем пользовательский порядок серверов.
    _applyServerOrder();
  }

  // ---- настройки ----

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _storage.setStr('theme_mode', _themeToStr(m));
    notifyListeners();
  }

  void setNotificationsEnabled(bool v) {
    notificationsEnabled = v;
    _storage.setBool('notifications', v);
    notifyListeners();
  }

  void setAutoConnect(bool v) {
    autoConnect = v;
    _storage.setBool('auto_connect', v);
    notifyListeners();
  }

  void setGlobeAnimations(bool v) {
    globeAnimations = v;
    _storage.setBool('globe_anim', v);
    notifyListeners();
  }

  void setLang(String v) {
    lang = v;
    L.current = v;
    _storage.setStr('lang', v);
    notifyListeners();
  }

  void setKillSwitch(bool v) {
    killSwitch = v;
    _storage.setBool('kill_switch', v);
    notifyListeners();
  }

  void setBypassRu(bool v) {
    bypassRu = v;
    _storage.setBool('bypass_ru', v);
    notifyListeners();
  }

  void setSoundEnabled(bool v) {
    soundEnabled = v;
    _storage.setBool('sound', v);
    notifyListeners();
  }

  void setVibrationEnabled(bool v) {
    vibrationEnabled = v;
    _storage.setBool('vibration', v);
    notifyListeners();
  }

  ThemeMode _themeFromStr(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
  String _themeToStr(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  // ---- режим/выбор сервера ----

  void setMode(GlobalMode m) {
    mode = m;
    _storage.globalMode = m == GlobalMode.manual ? 'manual' : 'ai';
    notifyListeners();
  }

  void setManualServer(String serverId) {
    manualServerId = serverId;
    _storage.manualServerId = serverId;
    // Ручной выбор = ручной режим.
    mode = GlobalMode.manual;
    _storage.globalMode = 'manual';
    notifyListeners();
    // Если туннель уже поднят (или поднимается) — переключаемся на выбранный
    // сервер на лету. Иначе менялся бы только визуал, а туннель оставался старым.
    if (isConnected || _stage == VpnStage.connecting || telegramOnly) {
      _reconnectTo();
    }
  }

  /// Жёсткое переподключение к текущему выбранному серверу: полностью гасим
  /// туннель, ДОЖИДАЕМСЯ реального отключения ядра, затем поднимаем заново.
  /// Без ожидания нативный сервис не успевает пересоздать ядро с новым конфигом.
  bool _switching = false;
  Future<void> _reconnectTo() async {
    if (_switching) return;
    _switching = true;
    try {
      telegramOnly = false;
      final srv = activeServer;
      if (srv == null) return;
      // Переключение «на лету»: startV2Ray с новым конфигом сам делает
      // stopCore+startCore на том же socks-порту (НЕ полный disconnect —
      // тот на EMUI не переподнимается). Так туннель реально меняет сервер.
      _log('Переключение на ${srv.flag} ${srv.title}…', LogKind.connect);
      try {
        await vpn.connect(srv, rules: rules, net: net, blockedApps: blockedApps);
        _notify('Сервер: ${srv.flag} ${srv.countryName}');
      } catch (e) {
        _log('Ошибка переключения: $e', LogKind.error);
        _notify('Не удалось переключиться на ${srv.countryName}');
      }
    } finally {
      _switching = false;
    }
  }

  /// Сервер, выбранный для общего трафика (с учётом режима).
  VpnServer? get activeServer {
    if (servers.isEmpty) return null;
    if (mode == GlobalMode.manual && manualServerId != null) {
      return servers.firstWhere(
        (s) => s.id == manualServerId,
        orElse: () => _bestServer(),
      );
    }
    return _bestServer(); // ИИ-режим: лучший по пингу
  }

  /// «Лучший» сервер = минимальный измеренный пинг среди ПОДДЕРЖИВАЕМЫХ ядром
  /// (Hysteria2/TUIC пропускаем — VPN на них не поднимется). Если поддерживаемых
  /// нет — берём из всех (чтобы хоть что-то показать).
  VpnServer _bestServer() {
    final pool = servers.where((s) => s.xraySupported).toList();
    final list = pool.isNotEmpty ? pool : servers;
    // Сначала по надёжности транспорта (Reality лучше httpupgrade), потом по пингу.
    int score(VpnServer s) => s.pingMs > 0 ? s.pingMs : (1 << 30);
    list.sort((a, b) {
      final t = a.transportPriority.compareTo(b.transportPriority);
      return t != 0 ? t : score(a).compareTo(score(b));
    });
    return list.first;
  }

  /// Кандидаты для подключения с failover: поддерживаемые серверы по возрастанию
  /// пинга. В ручном режиме выбранный сервер идёт первым.
  List<VpnServer> _connectCandidates() {
    var pool = servers.where((s) => s.xraySupported).toList();
    if (pool.isEmpty) pool = List.of(servers);
    // Reality → обычный tcp → httpupgrade (последний падает на Android),
    // внутри группы — по возрастанию пинга.
    pool.sort((a, b) {
      final t = a.transportPriority.compareTo(b.transportPriority);
      if (t != 0) return t;
      final pa = a.pingMs > 0 ? a.pingMs : 1 << 30;
      final pb = b.pingMs > 0 ? b.pingMs : 1 << 30;
      return pa.compareTo(pb);
    });
    if (mode == GlobalMode.manual && manualServerId != null) {
      final i = pool.indexWhere((s) => s.id == manualServerId);
      if (i > 0) {
        final sel = pool.removeAt(i);
        pool.insert(0, sel);
      }
    }
    return pool;
  }

  // ---- подключение ----

  bool _connecting = false;

  Future<void> connect() async {
    if (_connecting) return;
    telegramOnly = false;
    if (servers.isEmpty) {
      lastError = 'Нет серверов — сначала импортируй подписку';
      _log('Подключение отклонено: нет серверов', LogKind.error);
      notifyListeners();
      return;
    }
    final ok = await vpn.requestPermission();
    if (!ok) {
      lastError = 'Нет разрешения на VPN';
      _log('Нет разрешения на VPN', LogKind.error);
      notifyListeners();
      return;
    }
    final candidates = _connectCandidates();
    if (candidates.isEmpty) {
      lastError = 'Нет совместимых серверов (нужен VLESS/VMess/Trojan/SS)';
      _log(lastError!, LogKind.error);
      _notify(lastError!);
      notifyListeners();
      return;
    }
    _connecting = true;
    try {
      // Перебираем серверы, пока какой-нибудь реально не подключится (failover —
      // часть серверов может быть нерабочей).
      for (final srv in candidates) {
        _log('Подключение к ${srv.flag} ${srv.title} (${srv.protocol.label})…',
            LogKind.connect);
        try {
          final success = await _tryConnect(srv);
          if (success) {
            manualServerId = srv.id; // фиксируем рабочий сервер
            _storage.manualServerId = srv.id;
            _notify('Подключено: ${srv.flag} ${srv.countryName}'
                '${mode == GlobalMode.ai ? ' · выбран ИИ' : ''}');
            return;
          }
          _log('${srv.title}: не ответил, пробую следующий', LogKind.notice);
        } catch (e) {
          _log('${srv.title}: $e', LogKind.error);
        }
      }
      lastError = 'Не удалось подключиться ни к одному серверу';
      _notify('Не удалось подключиться — проверь подписку');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Пытается поднять туннель к [srv]. Возвращает true, если connect не выбросил
  /// ошибку (туннель запущен). НЕ рвёт соединение по таймауту статуса — на
  /// EMUI/MIUI статус «CONNECTED» может не дойти, хотя туннель работает; рвать
  /// его и перебирать дальше = бесконечное переподключение. Поэтому failover
  /// срабатывает только на реальную ошибку connect() (брошенное исключение).
  Future<bool> _tryConnect(VpnServer srv) async {
    final completer = Completer<bool>();
    final sub = vpn.stageStream.listen((s) {
      if (s == VpnStage.connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });
    try {
      await vpn.connect(srv, rules: rules, net: net, blockedApps: blockedApps); // бросит на неподдерживаемом протоколе
    } catch (e) {
      await sub.cancel();
      rethrow; // → следующий кандидат
    }
    // ждём подтверждения статуса, но даже без него считаем успехом (туннель
    // запущен; ядро через 2.5 с само выставит connected оптимистично).
    await completer.future
        .timeout(const Duration(seconds: 6), onTimeout: () => true);
    await sub.cancel();
    return true;
  }

  /// Бесплатный режим: туннелируем ТОЛЬКО Telegram, остальное — напрямую.
  /// Доступен до оплаты. Использует те же серверы (нужен хотя бы один).
  Future<void> connectTelegramOnly() async {
    if (servers.isEmpty) {
      // TODO(backend): бесплатный общий конфиг (свой uuid с лимитом) — отдать
      // отдельным эндпоинтом. Пока для демо синтезируем витринный сервер.
      servers = [
        VpnServer(
          protocol: VpnProtocol.vless,
          name: 'Free Telegram',
          address: 'nl1.ug-connect.site',
          port: 443,
          raw: 'vless://free@nl1.ug-connect.site:443#Free',
          displayName: 'Нидерланды',
        ),
      ];
    }
    telegramOnly = true;
    final srv = activeServer!;
    final ok = await vpn.requestPermission();
    if (!ok) {
      lastError = 'Нет разрешения на VPN';
      notifyListeners();
      return;
    }
    _log('Бесплатный режим: только Telegram → ${srv.flag} ${srv.title}',
        LogKind.connect);
    await vpn.connect(srv, rules: rules, net: net, blockedApps: blockedApps);
    _notify('🆓 Бесплатный VPN включён — работает только для Telegram');
  }

  Future<void> disconnect() async {
    _log('Отключено', LogKind.disconnect);
    await vpn.disconnect();
  }

  // ---- пинг ----

  static const _kPingType = 'ping_type'; // 'proxy' | 'tcp'
  static const _kPingUrl = 'ping_test_url';

  String get pingType => _storage.getStr(_kPingType, def: 'tcp');
  set pingType(String v) {
    _storage.setStr(_kPingType, v);
    notifyListeners();
  }

  String get pingTestUrl =>
      _storage.getStr(_kPingUrl, def: 'https://www.gstatic.com/generate_204');
  set pingTestUrl(String v) {
    _storage.setStr(_kPingUrl, v.trim());
    notifyListeners();
  }

  Future<void> pingAll() async {
    _setBusy(true);
    try {
      await _pingAllSilent();
    } finally {
      _setBusy(false);
    }
  }

  /// Тихий пинг (без индикатора busy).
  /// [background] = true (фоновый ИИ-пинг) — ВСЕГДА TCP: быстро и надёжно,
  /// не рвёт активный туннель. Ручная кнопка (background=false) уважает выбор
  /// пользователя в Настройки → Пинг (via Proxy — точнее, но медленнее).
  Future<void> _pingAllSilent({bool background = false}) async {
    // Быстро и реально, без «прыжков». Всё параллельно.
    //  • TCP — одиночный быстрый замер (как в Happ). При подключённом VPN
    //    результат <10 мс = артефакт локального сокета туннеля → игнорируем,
    //    оставляем прошлое реальное значение (пинг не прыгает на ~4 мс).
    //  • Proxy (getServerDelay) — реальная задержка ядра, оборачиваем в таймаут
    //    3 с, чтобы не «висел»; при таймауте оставляем прошлее значение.
    final viaProxy = pingType == 'proxy';
    await Future.wait(servers.map((s) async {
      int v;
      if (viaProxy) {
        v = await vpn
            .ping(s)
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
      } else {
        v = await tcpPing(s.address, s.port);
        if (isConnected && v > 0 && v < 10) v = -1; // артефакт туннеля
      }
      if (v > 0) s.pingMs = v; // не затираем прошлое валидное значение
    }));
    notifyListeners();
  }

  // ---- ИИ авто-пинг ----
  Timer? _aiTimer;

  void _startAiAutoPing() {
    _aiTimer?.cancel();
    // Каждые 30 сек в ИИ-режиме перемеряем пинги и выбираем лучшее; если активный
    // сервер «умер» — переключаемся (перебор серверов в connect).
    _aiTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mode != GlobalMode.ai || servers.isEmpty) return;
      await _pingAllSilent(background: true);
      if (isConnected) {
        final cur = activeServer;
        if (cur != null && cur.pingMs < 0) {
          _log('ИИ: ${cur.title} недоступен — переключаюсь на лучший',
              LogKind.notice);
          await connect();
        }
      }
    });
  }

  // ---- per-app правила ----

  void upsertRule(AppRule rule) {
    final i = rules.indexWhere((r) => r.appId == rule.appId);
    if (i >= 0) {
      rules[i] = rule;
    } else {
      rules.add(rule);
    }
    _saveRules();
    notifyListeners();
  }

  void removeRule(String appId) {
    rules.removeWhere((r) => r.appId == appId);
    _saveRules();
    notifyListeners();
  }

  void _loadRules() {
    final raw = _storage.appRulesJson;
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      rules = list
          .map((e) => AppRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      rules = [];
    }
  }

  void _saveRules() {
    _storage.appRulesJson =
        jsonEncode(rules.map((r) => r.toJson()).toList());
  }

  // ---- живой лог (что → куда сейчас) ----

  List<RouteEntry> get liveRoutes {
    if (!isConnected) return const [];
    final srv = activeServer;

    // Бесплатный режим: только Telegram через VPN, остальное — напрямую.
    if (telegramOnly) {
      return [
        RouteEntry(
          appName: _telegramAppName,
          serverName: srv?.title ?? '—',
          serverFlag: srv?.flag ?? '🌐',
        ),
        const RouteEntry(
          appName: 'Все остальные приложения',
          serverName: 'Напрямую',
          direct: true,
        ),
      ];
    }

    final entries = <RouteEntry>[];
    // Сначала явные per-app правила.
    for (final r in rules) {
      if (r.mode == RouteMode.direct) {
        entries.add(RouteEntry(appName: r.appName, serverName: 'Напрямую', direct: true));
      } else if (r.mode == RouteMode.manualServer && r.serverId != null) {
        final matches = servers.where((x) => x.id == r.serverId);
        final s = matches.isEmpty ? null : matches.first;
        entries.add(RouteEntry(
          appName: r.appName,
          serverName: s?.title ?? '—',
          serverFlag: s?.flag ?? '🌐',
        ));
      } else if (srv != null) {
        entries.add(RouteEntry(appName: r.appName, serverName: srv.title, serverFlag: srv.flag));
      }
    }
    // Остальной трафик — через активный сервер.
    if (srv != null) {
      entries.add(RouteEntry(
        appName: 'Все остальные приложения',
        serverName: srv.title,
        serverFlag: srv.flag,
      ));
    }
    return entries;
  }

  // ---- служебное ----

  void _setBusy(bool v) {
    busy = v;
    notifyListeners();
  }

  Future<void> logout() async {
    await disconnect();
    await _storage.clearAll();
    servers = [];
    rules = [];
    manualServerId = null;
    mode = GlobalMode.ai;
    telegramOnly = false;
    logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _aiTimer?.cancel();
    notice.dispose();
    vpn.dispose();
    super.dispose();
  }
}
