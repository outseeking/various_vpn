/// Центральное состояние приложения (ChangeNotifier + provider).
///
/// Связывает хранилище, бэкенд, парсер и VPN-ядро. Экраны читают это состояние
/// и дёргают его методы — вся логика здесь, UI остаётся «тонким».
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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
import '../services/auto_wifi_guard.dart';
import '../services/backend_api.dart';
import '../services/home_widget_sync.dart';
import '../services/ping.dart';
import '../services/vpn_status_probe.dart';
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
      _pushWidget();
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
      // График сэмплит ровный 1-секундный таймер (_startSession) — здесь только
      // обновляем мгновенные значения, чтобы цифры скорости были живыми.
      notifyListeners();
    });
    _startAiAutoPing();
    _pushWidget(); // стартовое состояние домашнего виджета
  }

  /// Отправить текущее состояние в домашний виджет Android. Кнопки виджета
  /// (вкл/выкл, пинг) обрабатываются нативно — здесь только данные для показа
  /// и параметры (хост/порт/тип пинга), которыми пользуется нативный ресивер.
  void _pushWidget() {
    final a = activeServer;
    HomeWidgetSync.push(
      connected: isConnected,
      countryCode: a?.countryCode ?? '',
      server: a?.title ?? (a?.countryName ?? ''),
      host: a?.address ?? '',
      port: a?.port ?? 0,
      pingType: pingType,
      pingMs: a?.pingMs ?? -1,
    );
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

  /// Перемещение сервера по id: [dragId] встаёт на позицию [targetId]
  /// (drag-n-drop в компактной сетке). Направление учитываем, чтобы ощущалось
  /// естественно: тащим вперёд — встаём ПОСЛЕ цели, назад — ПЕРЕД целью
  /// (как в ReorderableListView).
  void moveServer(String dragId, String targetId) {
    if (dragId == targetId) return;
    final from = servers.indexWhere((e) => e.id == dragId);
    final to = servers.indexWhere((e) => e.id == targetId);
    if (from < 0 || to < 0) return;
    final s = servers.removeAt(from);
    var insertAt = servers.indexWhere((e) => e.id == targetId);
    if (insertAt < 0) insertAt = servers.length;
    if (from < to) insertAt += 1; // двигаем вперёд — встаём после цели
    insertAt = insertAt.clamp(0, servers.length);
    servers.insert(insertAt, s);
    _serverOrder = servers.map((e) => e.id).toList();
    _storage.setStr('server_order', _serverOrder.join('\n'));
    notifyListeners();
  }

  /// Следующая/предыдущая папка по кругу (для переключения свайпом).
  void cycleFolder(int dir) {
    final all = <String>['', ...folders];
    if (all.length < 2) return;
    final cur = all.indexOf(activeFolder);
    final next = (cur + dir) % all.length;
    setActiveFolder(all[next < 0 ? next + all.length : next]);
  }

  // Пользовательские имена серверов (переопределяют авто-название страны).
  Map<String, String> _customNames = {};
  void _persistCustomNames() =>
      _storage.setStr('custom_names', jsonEncode(_customNames));

  /// Переименовать сервер (пустое имя — вернуть авто-название страны).
  void renameServer(String id, String name) {
    final n = name.trim();
    if (n.isEmpty) {
      _customNames.remove(id);
    } else {
      _customNames[id] = n;
    }
    _persistCustomNames();
    for (final s in servers) {
      if (s.id == id) s.displayName = n.isEmpty ? s.countryName : n;
    }
    notifyListeners();
  }

  /// Удалить сервер из списка (и из своих серверов/порядка, если он там был).
  void removeServer(String id) {
    servers = servers.where((s) => s.id != id).toList();
    _serverOrder.remove(id);
    _storage.setStr('server_order', _serverOrder.join('\n'));
    _customRaws = _customRaws.where((raw) {
      final s = SubscriptionParser.parseLink(raw);
      return s == null || s.id != id;
    }).toList();
    _storage.setStr('custom_raws', _customRaws.join('\n'));
    _customNames.remove(id);
    _persistCustomNames();
    if (manualServerId == id) manualServerId = null;
    _storage.saveConfigsBlob(servers.map((s) => s.raw).join('\n'));
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
  bool autoRefreshSub = false; // авто-обновление подписки по таймеру
  int autoRefreshHours = 6; // интервал авто-обновления, ч (1/3/6/12/24)
  Timer? _subRefreshTimer;
  bool onDemand = false; // режим «по требованию»: авто-подключение при запуске
  bool globeAnimations = true;
  bool liteMode = false; // режим экономии для слабых устройств
  bool get animationsOn => globeAnimations && !liteMode;
  bool compactServers = false; // компактный вид серверов (2 в строке)

  void setCompactServers(bool v) {
    compactServers = v;
    _storage.setBool('compact_servers', v);
    notifyListeners();
  }

  // ---- папки серверов ----
  List<String> folders = []; // пользовательские папки (кроме «Все серверы»)
  Map<String, String> _serverFolder = {}; // id сервера → имя папки
  String activeFolder = ''; // '' = «Все серверы»

  /// Серверы для показа с учётом выбранной папки.
  List<VpnServer> get visibleServers => activeFolder.isEmpty
      ? servers
      : servers.where((s) => _serverFolder[s.id] == activeFolder).toList();

  String? folderOf(String id) => _serverFolder[id];

  void _persistFolders() {
    _storage.setStr('folders', folders.join('\n'));
    _storage.setStr('server_folders', jsonEncode(_serverFolder));
  }

  void setActiveFolder(String f) {
    activeFolder = f;
    notifyListeners();
  }

  void addFolder(String name) {
    final n = name.trim();
    if (n.isEmpty || folders.contains(n)) return;
    folders = [...folders, n];
    _persistFolders();
    notifyListeners();
  }

  void removeFolder(String name) {
    folders = folders.where((f) => f != name).toList();
    _serverFolder.removeWhere((k, v) => v == name);
    if (activeFolder == name) activeFolder = '';
    _persistFolders();
    notifyListeners();
  }

  void setServerFolder(String id, String? folder) {
    if (folder == null || folder.isEmpty) {
      _serverFolder.remove(id);
    } else {
      _serverFolder[id] = folder;
    }
    _persistFolders();
    notifyListeners();
  }
  bool bypassRu = true;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  String lang = 'ru'; // 'ru' | 'en'

  // ---- авто-VPN в незнакомых сетях ----
  bool autoWifiProtect = false; // включать VPN в НЕдоверенных Wi-Fi
  Set<String> trustedSsids = {}; // доверенные сети (VPN не навязываем)

  // ---- сплит-туннелирование (per-app) ----
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
  bool smartAi = true; // умный доступ к ИИ (ChatGPT/Gemini/Claude через туннель)

  /// Собранные сетевые опции для передачи в ядро при connect.
  NetOptions get net => NetOptions(
        dns: customDns.trim().isEmpty
            ? const []
            : customDns.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        bypassRu: bypassRu,
        ipStrategy: ipStrategy,
        // авто-фрагментация на повторных попытках — обходит DPI, режущий TLS-hello
        fragment: fragment || _forceFragment,
        directDomains: splitUrls.toList(),
        smartAi: smartAi,
        adBlock: adBlock,
        aiDomains: _aiDomains,
        ruDomains: _ruDomains,
        adDomains: _adDomains,
        telegramOnly: telegramOnly,
      );

  bool adBlock = false; // блокировка рекламы/трекеров в туннеле
  void setAdBlock(bool v) {
    adBlock = v;
    _storage.setBool('ad_block', v);
    notifyListeners();
    if (isConnected) _reconnectTo();
  }

  bool _forceFragment = false; // авто-фрагментация на повторной попытке (анти-DPI)


  // Динамические списки маршрутизации (тянутся из панели, кэшируются локально).
  List<String> _aiDomains = const [];
  List<String> _ruDomains = const [];
  List<String> _adDomains = const [];

  void _loadCachedRouting() {
    final ai = _storage.getStr('routing_ai', def: '');
    final ru = _storage.getStr('routing_ru', def: '');
    final ad = _storage.getStr('routing_ad', def: '');
    if (ai.isNotEmpty) _aiDomains = ai.split('\n').where((e) => e.isNotEmpty).toList();
    if (ru.isNotEmpty) _ruDomains = ru.split('\n').where((e) => e.isNotEmpty).toList();
    if (ad.isNotEmpty) _adDomains = ad.split('\n').where((e) => e.isNotEmpty).toList();
  }

  /// Тянет актуальные списки маршрутизации из панели (ИИ + РФ-домены). При смене
  /// CDN у OpenAI/Anthropic достаточно поправить список в панели — приложение
  /// подхватит без обновления. Кэшируется, чтобы работать оффлайн.
  Future<void> loadRouting() async {
    try {
      final r = await http
          .get(Uri.parse('${Brand.panelBase}/api/app/routing'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final ai = (d['ai_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final ru = (d['ru_direct_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final ad = (d['ad_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (ai.isNotEmpty) {
        _aiDomains = ai;
        _storage.setStr('routing_ai', ai.join('\n'));
      }
      if (ru.isNotEmpty) {
        _ruDomains = ru;
        _storage.setStr('routing_ru', ru.join('\n'));
      }
      if (ad.isNotEmpty) {
        _adDomains = ad;
        _storage.setStr('routing_ad', ad.join('\n'));
      }
    } catch (_) {}
  }

  void setSmartAi(bool v) {
    smartAi = v;
    _storage.setBool('smart_ai', v);
    notifyListeners();
    if (isConnected) _reconnectTo(); // применяем маршрутизацию сразу
  }

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
    // Бесплатный режим (только Telegram) переживает перезапуск — иначе после
    // перезахода серверы и режим «слетали».
    telegramOnly = _storage.getBool('telegram_only', def: false);
    // Доступ, выданный при импорте подписки, тоже сохраняется (замки открыты).
    if (_storage.getBool('access_granted', def: false)) {
      subActive = true;
      subLoaded = true;
    }
    autoRefreshSub = _storage.getBool('auto_refresh_sub', def: false);
    autoRefreshHours = _storage.getInt('auto_refresh_hours', def: 6);
    onDemand = _storage.getBool('on_demand', def: false);
    adBlock = _storage.getBool('ad_block', def: false);
    liteMode = _storage.getBool('lite_mode', def: false);
    compactServers = _storage.getBool('compact_servers', def: false);
    final foldersRaw = _storage.getStr('folders', def: '');
    folders = foldersRaw.isEmpty
        ? []
        : foldersRaw.split('\n').where((e) => e.isNotEmpty).toList();
    final sfRaw = _storage.getStr('server_folders', def: '');
    if (sfRaw.isNotEmpty) {
      try {
        _serverFolder = (jsonDecode(sfRaw) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }
    autoWifiProtect = _storage.getBool('auto_wifi', def: false);
    final tsRaw = _storage.getStr('trusted_ssids', def: '');
    trustedSsids = tsRaw.isEmpty ? {} : tsRaw.split('\n').toSet();
    _initAutoWifi();
    final cr = _storage.getStr('custom_raws', def: '');
    _customRaws = cr.isEmpty ? const [] : cr.split('\n').where((e) => e.isNotEmpty).toList();
    _loadCachedRouting();
    // Тумблер анимаций убран из настроек — анимации глобуса всегда включены
    // (иначе у тех, кто раньше выключил, звёзды/падающие звёзды не работали бы).
    globeAnimations = true;
    _storage.setBool('globe_anim', true);
    bypassRu = _storage.getBool('bypass_ru', def: true);
    soundEnabled = _storage.getBool('sound', def: true);
    vibrationEnabled = _storage.getBool('vibration', def: true);
    ipStrategy = IpStrategy.values.firstWhere(
      (e) => e.name == _storage.getStr('ip_strategy', def: 'auto'),
      orElse: () => IpStrategy.auto,
    );
    customDns = _storage.getStr('custom_dns', def: '');
    fragment = _storage.getBool('fragment', def: false);
    smartAi = _storage.getBool('smart_ai', def: true);
    splitEnabled = _storage.getBool('split_enabled', def: false);
    splitThroughVpn = _storage.getBool('split_through', def: false);
    final splitRaw = _storage.getStr('split_apps', def: '');
    splitApps = splitRaw.isEmpty ? {} : splitRaw.split('\n').toSet();
    final orderRaw = _storage.getStr('server_order', def: '');
    _serverOrder = orderRaw.isEmpty ? [] : orderRaw.split('\n');
    final cnRaw = _storage.getStr('custom_names', def: '');
    if (cnRaw.isNotEmpty) {
      try {
        _customNames = (jsonDecode(cnRaw) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }
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
        _allTime['servers'] ??= {};
        _allTime['days'] ??= {};
        _migrateCountryStats(); // свернуть старые дубли RU/EN → коды стран
      } catch (_) {}
    }
    _loadRules();
    final blob = await _storage.loadConfigsBlob();
    if (blob != null && blob.isNotEmpty) {
      servers = SubscriptionParser.parseContent(blob);
      _assignDisplayNames();
    }
    _appendCustomServers(); // восстановить свои JSON-серверы после перезапуска
    _rescheduleSubRefresh(); // запустить авто-обновление подписки, если включено
    // Отмечаем день серии (огонёк) при КАЖДОМ заходе в приложение, а не только
    // при подключении VPN — иначе «зашёл сегодня», а день не засчитался. Сервер
    // сам игнорирует повторную отметку в тот же день (накрутки нет).
    _reportStreak();
    notifyListeners();
    // Мгновенно восстановить состояние «подключено» при повторном заходе. Плагин
    // сообщает статус только broadcast'ами с задержкой (~5 с на EMUI после
    // удаления из «недавних»), поэтому спрашиваем ОС напрямую: активна ли VPN
    // сеть прямо сейчас. Если да — сразу показываем «подключено», не дожидаясь
    // плагина. Реальный статус потом подтвердит/поправит через stageStream.
    _restoreVpnStateOnLaunch();
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

  /// Мгновенное восстановление «подключено» при заходе (см. вызов в load()).
  Future<void> _restoreVpnStateOnLaunch() async {
    if (_stage == VpnStage.connected || _connecting) return;
    // только если МЫ были подключены (иначе активной может быть чужая VPN)
    if (!_storage.getBool('was_connected', def: false)) return;
    final active = await VpnStatusProbe.isSystemVpnActive();
    if (!active) return;
    // ОС говорит: VPN-сеть активна. Показываем «подключено» немедленно.
    if (_stage != VpnStage.connected && !_connecting) {
      _stage = VpnStage.connected;
      _startSession();
      _pushWidget();
      notifyListeners();
      _log('Восстановлено активное подключение', LogKind.notice);
    }
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
        _appendCustomServers(); // не теряем свои серверы после синка
        await _storage.saveConfigsBlob(raw);
        notifyListeners();
        _pingAllSilent(background: true);
      }
    } catch (_) {
      // панель недоступна — работаем на сохранённых серверах
    }
    loadRouting(); // свежие списки маршрутизации (ИИ/РФ) из панели
    _rescheduleSubRefresh(); // запустить авто-обновление подписки, если включено
    maybeAutoConnectOnLaunch(); // «Автоподключение» — поднять VPN при запуске
  }

  // ---- логи/уведомления ----

  void _log(String text, [LogKind kind = LogKind.info]) {
    logs.insert(0, LogEntry(text, kind));
    if (logs.length > 300) logs.removeRange(300, logs.length);
    // дублируем в системный лог (logcat) — для диагностики через adb
    developer.log(text, name: 'VaVPN');
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
  final List<double> speedHistory = []; // последние ~40 точек (КБ/с, принято)
  final List<double> speedHistoryUp = []; // последние ~40 точек (КБ/с, отдано)

  Duration get sessionDuration =>
      _sessionStart == null ? Duration.zero : DateTime.now().difference(_sessionStart!);

  void _startSession() {
    _sessionStart = DateTime.now();
    bytesDown = 0;
    bytesUp = 0;
    speedDownKbps = 0;
    speedUpKbps = 0;
    _lastTrafficAt = null;
    final a = activeServer;
    _sessionCountry = a?.countryName ?? '';
    _sessionCC = a?.countryCode ?? '';
    _sessionServerId = a?.id ?? '';
    _sessionServerName = a?.title ?? (a?.countryName ?? '');
    // Засеиваем график плоской базовой линией, чтобы он появлялся МГНОВЕННО при
    // подключении (а не пустым первые секунды до прихода трафика). Реальные
    // точки плавно вытеснят нули.
    speedHistory
      ..clear()
      ..addAll(List<double>.filled(16, 0.0));
    speedHistoryUp
      ..clear()
      ..addAll(List<double>.filled(16, 0.0));
    if (vibrationEnabled) {
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate(); // реальная вибрация — заметнее, чем haptic
    }
    if (soundEnabled) Sound.connect();
    _sessionTimer?.cancel();
    // Тик раз в секунду: обновляем время И РОВНО СЭМПЛИРУЕМ график (даже если
    // ядро шлёт трафик рывками — линия всегда двигается, не «залипает»). Если
    // трафика не было >2.5 c — плавно роняем скорость к нулю (график честный).
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final stale = _lastTrafficAt == null ||
          DateTime.now().difference(_lastTrafficAt!).inMilliseconds > 2500;
      if (stale) {
        speedDownKbps *= 0.4;
        speedUpKbps *= 0.4;
        if (speedDownKbps < 1) speedDownKbps = 0;
        if (speedUpKbps < 1) speedUpKbps = 0;
      }
      void push(List<double> h, double v) {
        final prev = h.isEmpty ? v : h.last;
        h.add(prev * 0.5 + v * 0.5); // лёгкое сглаживание
        if (h.length > 40) h.removeAt(0);
      }
      push(speedHistory, speedDownKbps);
      push(speedHistoryUp, speedUpKbps);
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
  int _wdLastBytes = 0; // сколько скачано на момент прошлой проверки
  DateTime? _lastAutoReconnect; // кулдаун авто-переподключений

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _healthFails = 0;
    _wdLastBytes = bytesDown;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!isConnected || _switching) return;

      // 1) Если трафик ИДЁТ (байты растут) — туннель точно жив, ничего не делаем.
      //    Это главная защита: пока пользователь чем-то пользуется, не трогаем.
      if (bytesDown > _wdLastBytes) {
        _wdLastBytes = bytesDown;
        _healthFails = 0;
        return;
      }

      // 2) Трафика нет — это может быть просто простой. Делаем лёгкую пробу
      //    через туннель (с одним ретраем), чтобы не спутать простой со сбоем.
      final ok = await _tunnelAlive();
      _wdLastBytes = bytesDown;
      if (ok) {
        _healthFails = 0;
        return;
      }
      _healthFails++;

      // 3) Реконнект — только после 3 провалов подряд (~90 с без связи) И не
      //    чаще раза в 3 минуты. Так живой туннель не рвётся из-за ложной пробы.
      //    Авто-восстановление работает только при включённом «По требованию».
      final now = DateTime.now();
      final cooled = _lastAutoReconnect == null ||
          now.difference(_lastAutoReconnect!).inSeconds > 180;
      if (onDemand && _healthFails >= 3 && cooled) {
        _healthFails = 0;
        _lastAutoReconnect = now;
        _log('VPN долго не отвечает — переподключаюсь автоматически',
            LogKind.notice);
        await _reconnectTo();
      }
    });
  }

  /// Лёгкая проба живости туннеля с одним повтором (меньше ложных срабатываний).
  Future<bool> _tunnelAlive() async {
    for (var i = 0; i < 2; i++) {
      try {
        final r = await http
            .get(Uri.parse('https://www.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 204 || r.statusCode == 200) return true;
      } catch (_) {}
      if (i == 0) await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _healthFails = 0;
  }

  void _stopSession() {
    // Уведомление: страна + сколько времени пользовались сервером.
    final dur = sessionDuration;
    // копим минуты сессии — из них сервер начисляет «заморозки» серии (≥25 ч/нед)
    _lastSessionMinutes += dur.inMinutes;
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
    if (vibrationEnabled) {
      HapticFeedback.mediumImpact();
      HapticFeedback.vibrate();
    }
    if (soundEnabled) Sound.disconnect();
    notifyListeners();
  }

  // ---- статистика за всё время (накопительная, переживает перезапуск) ----
  // {down,up: int; countries: {имя: int}; days: {yyyy-mm-dd: int}}
  Map<String, dynamic> _allTime =
      {'down': 0, 'up': 0, 'countries': {}, 'servers': {}, 'days': {}};
  String _sessionCountry = '';
  String _sessionCC = ''; // код страны текущей сессии (ключ статистики)
  String _sessionServerId = ''; // id сервера текущей сессии (для по-серверной)
  String _sessionServerName = '';

  int get allTimeDown => (_allTime['down'] as num).toInt();
  int get allTimeUp => (_allTime['up'] as num).toInt();

  /// Топ стран по трафику: список (код страны, байты), по убыванию.
  /// Ключ — двухбуквенный код (DE/NL/FI…), имя берётся через [countryNameOf].
  List<MapEntry<String, int>> get topCountries {
    final m = (_allTime['countries'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()));
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Локализованное имя страны по коду (для экрана статистики).
  String countryNameOf(String cc) {
    final en = L.current == 'en';
    return switch (cc) {
      'DE' => en ? 'Germany' : 'Германия',
      'NL' => en ? 'Netherlands' : 'Нидерланды',
      'FI' => en ? 'Finland' : 'Финляндия',
      'RU' => en ? 'Russia' : 'Россия',
      'US' => en ? 'USA' : 'США',
      'GB' => en ? 'United Kingdom' : 'Великобритания',
      _ => cc,
    };
  }

  /// Разбивка по серверам одной страны: (имя сервера, скачано), по убыванию.
  /// Варианты одного сервера (TCP/gRPC на разных портах = разные id, но одно
  /// имя) сводятся в одну строку — иначе «Германия 1» дублировалась бы.
  List<MapEntry<String, int>> serverStatsForCountry(String cc) {
    final sv = (_allTime['servers'] as Map?) ?? const {};
    final byName = <String, int>{};
    sv.forEach((k, v) {
      final rec = v as Map;
      if ((rec['cc'] ?? '').toString() == cc) {
        var name = (rec['name'] ?? '').toString();
        if (name.isEmpty) name = k.toString();
        byName[name] = (byName[name] ?? 0) + ((rec['down'] ?? 0) as num).toInt();
      }
    });
    final out = byName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return out;
  }

  /// Отдача по серверам одной страны (для второй метрики в drill-down).
  /// Суммирует все варианты сервера с этим именем.
  int serverUpForCountry(String cc, String name) {
    final sv = (_allTime['servers'] as Map?) ?? const {};
    var up = 0;
    for (final v in sv.values) {
      final rec = v as Map;
      if ((rec['cc'] ?? '') == cc && ((rec['name'] ?? '') == name)) {
        up += ((rec['up'] ?? 0) as num).toInt();
      }
    }
    return up;
  }

  /// Свёртка старой статистики (ключи-имена стран RU/EN) в коды стран.
  /// Нужна один раз при первом запуске новой версии — устраняет дубли
  /// «Германия» и «Germany» в списке любимых стран.
  void _migrateCountryStats() {
    final c = (_allTime['countries'] as Map?) ?? {};
    var needs = false;
    for (final k in c.keys) {
      final s = k.toString();
      if (!(s.length == 2 && s == s.toUpperCase())) {
        needs = true;
        break;
      }
    }
    if (!needs) return;
    final migrated = <String, int>{};
    c.forEach((k, v) {
      final cc = _nameToCC(k.toString());
      migrated[cc] = (migrated[cc] ?? 0) + (v as num).toInt();
    });
    _allTime['countries'] = migrated;
    _storage.setStr('alltime_stats', jsonEncode(_allTime));
  }

  static String _nameToCC(String s) {
    final t = s.trim();
    if (t.length == 2 && t == t.toUpperCase()) return t;
    return switch (t) {
      'Германия' || 'Germany' => 'DE',
      'Нидерланды' || 'Netherlands' => 'NL',
      'Финляндия' || 'Finland' => 'FI',
      'Россия' || 'Russia' => 'RU',
      'США' || 'USA' => 'US',
      'Великобритания' || 'United Kingdom' => 'GB',
      _ => t.isEmpty ? '??' : t,
    };
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
    if (_sessionCC.isNotEmpty) {
      final c = (_allTime['countries'] as Map);
      c[_sessionCC] = ((c[_sessionCC] ?? 0) as num).toInt() + bytesDown;
    }
    // по-серверная разбивка (для drill-down внутри страны)
    if (_sessionServerId.isNotEmpty) {
      final sv = (_allTime['servers'] as Map);
      final rec = (sv[_sessionServerId] as Map?) ?? <String, dynamic>{};
      rec['down'] = ((rec['down'] ?? 0) as num).toInt() + bytesDown;
      rec['up'] = ((rec['up'] ?? 0) as num).toInt() + bytesUp;
      rec['cc'] = _sessionCC;
      rec['name'] = _sessionServerName;
      sv[_sessionServerId] = rec;
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
      supportChat.add(SupportMessage(
        '✅ Обращение принято! Обычно отвечаем за 5–15 минут. '
        'Ответ придёт прямо сюда 💬',
        fromUser: false,
      ));
      notifyListeners();
    } catch (_) {
      supportChat.add(SupportMessage(
        'Не удалось отправить сейчас — проверь интернет и попробуй ещё раз.',
        fromUser: false,
      ));
      notifyListeners();
    }
  }

  /// Отправляет файл/фото в поддержку (multipart → панель → админам в Telegram).
  Future<bool> sendSupportFile(String path, String filename) async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) {
      supportChat.add(SupportMessage(
        'Чтобы отправлять файлы, привяжи Telegram в профиле.',
        fromUser: false));
      notifyListeners();
      return false;
    }
    supportChat.add(SupportMessage('📎 $filename', fromUser: true));
    notifyListeners();
    try {
      final req = http.MultipartRequest(
          'POST', Uri.parse('${Brand.panelBase}/api/app/support/file'))
        ..fields['tg_id'] = tg
        ..files.add(await http.MultipartFile.fromPath('file', path));
      final resp = await req.send().timeout(const Duration(seconds: 40));
      final ok = resp.statusCode == 200;
      supportChat.add(SupportMessage(
        ok ? '✅ Файл отправлен — мы его получили 💙'
           : 'Не удалось отправить файл. Попробуй ещё раз.',
        fromUser: false));
      notifyListeners();
      return ok;
    } catch (_) {
      supportChat.add(SupportMessage(
        'Не удалось отправить файл — проверь интернет.', fromUser: false));
      notifyListeners();
      return false;
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
      // Защита от «пропадания»: если панель на миг вернула пусто (сообщение
      // ещё синхронизируется на сервере), а у нас уже есть локальная переписка —
      // НЕ затираем её. Перерисовываем из панели только когда там реально данные.
      if (list.isEmpty && supportChat.isNotEmpty) return;
      supportChat
        ..clear()
        ..addAll(list.map((m) => SupportMessage(
              (m['body'] ?? '').toString(),
              fromUser: m['from_admin'] != true,
            )));
      // если есть обращение, но ответа админа ещё нет — показываем ожидание
      final hasUserMsg = list.any((m) => m['from_admin'] != true);
      final hasAdminMsg = list.any((m) => m['from_admin'] == true);
      if (hasUserMsg && !hasAdminMsg) {
        supportChat.add(SupportMessage(
          '⏳ Мы получили ваше обращение и скоро ответим прямо здесь 💬',
          fromUser: false,
        ));
      }
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

  // ---- статус подписки (для карточки на главной) ----
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
    // Показываем РЕАЛЬНЫЙ статус с бэкенда для всех, включая владельца, — иначе
    // дата в приложении расходится с ботом (раньше админу хардкодилось «+30»).
    final st = await _api.subStatus(tg);
    if (st != null) {
      subActive = st.active;
      subUntil = st.until;
    }
    // Владелец всё равно имеет доступ к премиум-UI, даже если бэкенд не ответил.
    final idNum = int.tryParse(tg);
    if (idNum != null && _adminIds.contains(idNum)) subActive = true;
    subLoaded = true;
    if (subActive) await _onSubActivated();
    notifyListeners();
  }

  /// Вызывается, когда подписка стала активной (привязали TG / купили): выходим
  /// из бесплатного режима и подтягиваем полный список серверов из панели —
  /// чтобы всё появилось СРАЗУ, без перезахода в приложение.
  Future<void> _onSubActivated() async {
    if (telegramOnly) {
      telegramOnly = false;
      _storage.setBool('telegram_only', false);
      if (isConnected) await _safeDisconnect(); // free-туннель больше не нужен
    }
    if (!hasServers) {
      final servs = <VpnServer>[];
      await _mergePanelServers(servs);
      if (servs.isNotEmpty) {
        servers = servs;
        _assignDisplayNames();
        await _storage.saveConfigsBlob(servers.map((s) => s.raw).join('\n'));
        _storage.subUrl = Brand.panelSub;
      }
    }
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
    // Голый числовой код — это Telegram-ID из бота: привязываем аккаунт и тянем
    // его персональную подписку (/vsub/{id}). Так «У меня есть ссылка или ID»
    // принимает и ID.
    if (RegExp(r'^\d{4,15}$').hasMatch(t)) {
      return importFromTgId(t);
    }
    final lower = t.toLowerCase(); // схема URL регистронезависима (Https:// тоже)
    final isUrl =
        (lower.startsWith('http://') || lower.startsWith('https://')) &&
            !t.contains('\n');
    return isUrl ? importFromUrl(t) : importFromContent(t);
  }

  /// Привязка по Telegram-ID из бота: сохраняем ID, тянем персональную подписку
  /// и статус. Успех, если подтянулись серверы ИЛИ подписка активна.
  Future<bool> importFromTgId(String id) async {
    setTgId(id);
    bool ok = false;
    try {
      ok = await importFromUrl(Brand.subForId(id));
    } catch (_) {
      ok = false;
    }
    await refreshSubStatus();
    await loadStreak();
    return ok || subActive || hasServers;
  }

  /// Проверяет, что сервер/подписка принадлежит НАШЕМУ VPN (хост оканчивается
  /// на Brand.rootDomain). Так пользователь не сможет добавить в приложение
  /// подписку стороннего сервиса.
  bool _isOurHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();
    if (h == Brand.rootDomain || h.endsWith('.${Brand.rootDomain}')) return true;
    // наши серверы часто заданы по IP, а не по домену
    return knownServerIps.contains(h);
  }

  /// true, если ВСЕ серверы из подписки — наши.
  bool _allOurs(List<VpnServer> list) =>
      list.isNotEmpty && list.every((s) => _isOurHost(s.address));

  /// Импорт по subscription-ссылке (грузим с бэкенда, парсим, сохраняем).
  Future<bool> importFromUrl(String url) async {
    _setBusy(true);
    try {
      final u = Uri.tryParse(url.trim());
      if (!_isOurHost(u?.host)) {
        lastError =
            'Можно добавлять только подписки Various VPN (ссылка должна вести '
            'на ${Brand.rootDomain} — получи её в нашем боте).';
        return false;
      }
      // URL уже проверен — ведёт на нашу панель, значит подписка наша.
      // Скачивание по самой ссылке НЕ обязано удаться: bot-ссылка nl1:8088/sub
      // отдаёт пустоту ИЛИ падает по TLS (HandshakeException). Это НЕ ошибка —
      // всё равно доливаем полный список серверов из панели (/vsub), который
      // всегда рабочий. Так «Импортировать» и «по QR» работают в любом случае.
      // Панель (/vsub) — ЕДИНЫЙ источник правды: ровно те серверы, что включил
      // админ (сейчас 8). Ссылку бота НЕ подмешиваем (её xtls-вариант на другом
      // порту давал «лишний» 9-й сервер). Если панель недоступна — берём ссылку.
      final panel = <VpnServer>[];
      await _mergePanelServers(panel);
      var parsed = panel;
      if (parsed.isEmpty) {
        try {
          final raw = await _api.fetchSubscription(url.trim());
          parsed = SubscriptionParser.parseContent(raw)
              .where((s) => s.xraySupported)
              .toList();
        } catch (e) {
          _log('Ссылка не скачалась ($e)', LogKind.info);
        }
      }
      if (parsed.isEmpty) {
        lastError = 'Не удалось получить серверы. Проверь интернет и попробуй ещё '
            'раз (или возьми свежую ссылку в боте).';
        return false;
      }
      servers = parsed;
      _assignDisplayNames();
      _appendCustomServers(); // не теряем свои JSON-серверы после обновления подписки
      _storage.subUrl = Brand.panelSub; // панель всегда рабочая для «Обновить»
      await _storage.saveConfigsBlob(servers.map((s) => s.raw).join('\n'));
      _grantAccessFromImport(); // импорт подписки = полный доступ (снимаем замки)
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

  /// Импорт подписки = у пользователя есть доступ: снимаем бесплатный режим и
  /// открываем все функции (замки). Пользователь получил ссылку в боте ПОСЛЕ
  /// оплаты — поэтому наличие нашей подписки-ссылки уже даёт полный доступ, без
  /// обязательной привязки Telegram ID.
  void _grantAccessFromImport() {
    if (telegramOnly) {
      telegramOnly = false;
      _storage.setBool('telegram_only', false);
    }
    subActive = true;
    subLoaded = true;
    _storage.setBool('access_granted', true);
  }

  /// Доливает в [into] все включённые серверы из панели (/vsub), которых там
  /// ещё нет (по id). Панель — самый надёжный источник полного списка стран.
  Future<void> _mergePanelServers(List<VpnServer> into) async {
    try {
      final praw = await _api.fetchSubscription(Brand.panelSub);
      final pservers = SubscriptionParser.parseContent(praw)
          .where((s) => s.xraySupported)
          .toList();
      final ids = into.map((s) => s.id).toSet();
      for (final s in pservers) {
        if (ids.add(s.id)) into.add(s);
      }
    } catch (_) {
      // панель недоступна — не критично, оставляем что есть
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
      if (!_allOurs(parsed)) {
        lastError = 'Можно добавлять только конфиги Various VPN '
            '(сервер должен быть на ${Brand.rootDomain}).';
        return false;
      }
      servers = parsed;
      _assignDisplayNames();
      _appendCustomServers();
      await _storage.saveConfigsBlob(content);
      _grantAccessFromImport(); // импорт конфигов = полный доступ
      _log('Импортировано серверов: ${servers.length}', LogKind.info);
      lastError = null;
      return true;
    } finally {
      _setBusy(false);
    }
  }

  /// Добавляет СВОИ серверы из JSON (до 5). Доступно только при активном
  /// подключении к Various VPN — это привилегия для наших пользователей.
  /// Принимает JSON-массив share-ссылок ["vless://…", …] или объектов
  /// [{"link":"vless://…"}, …]. В отличие от подписок, наши-проверки не
  /// применяются (это личные серверы пользователя).
  Future<bool> importCustomServers(String input) async {
    // Достаём ссылки. Поддерживаем:
    //  • ПОЛНЫЙ Xray-конфиг {"outbounds":[…]} (как экспортирует Happ/v2rayNG) —
    //    достаём vless/vmess/trojan из outbounds и строим share-ссылки;
    //  • JSON-массив ["vless://…"] или объекты [{"link":"…"}];
    //  • простой список ссылок построчно.
    final links = <String>[];
    final text = input.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['outbounds'] is List) {
        links.addAll(_linksFromXrayConfig(decoded));
      } else {
        final arr = decoded is List ? decoded : [decoded];
        for (final item in arr) {
          if (item is Map && item['outbounds'] is List) {
            links.addAll(_linksFromXrayConfig(item));
            continue;
          }
          final l = item is String
              ? item
              : (item is Map ? (item['link'] ?? item['url'] ?? '').toString() : '');
          if (l.trim().isNotEmpty) links.add(l.trim());
        }
      }
    } catch (_) {
      // не JSON — берём построчно
      for (final line in text.split(RegExp(r'[\r\n,]+'))) {
        final l = line.trim();
        if (l.contains('://')) links.add(l);
      }
    }
    final parsed = <VpnServer>[];
    final raws = <String>[];
    for (final link in links.take(5)) {
      final s = SubscriptionParser.parseLink(link);
      if (s != null) {
        parsed.add(s);
        raws.add(link);
      }
    }
    if (parsed.isEmpty) {
      lastError = 'Не удалось распознать ни одного сервера. Вставь vless://… '
          '(JSON-массивом или по одной ссылке на строку).';
      return false;
    }
    // сохраняем, чтобы пережили перезапуск и синк с панелью
    _customRaws = raws;
    _storage.setStr('custom_raws', raws.join('\n'));
    _appendCustomServers();
    lastError = null;
    _log('Добавлено своих серверов: ${parsed.length}', LogKind.info);
    notifyListeners();
    return true;
  }

  /// Достаёт vless/vmess/trojan-outbound'ы из полного Xray-конфига и строит
  /// share-ссылки (vless://…), которые понимает наше ядро.
  List<String> _linksFromXrayConfig(Map cfg) {
    final out = <String>[];
    final remark = (cfg['remarks'] ?? cfg['remark'] ?? '').toString();
    for (final o in (cfg['outbounds'] as List)) {
      if (o is! Map) continue;
      final link = _outboundToLink(o, remark);
      if (link != null) out.add(link);
    }
    return out;
  }

  String? _outboundToLink(Map o, String remark) {
    final proto = (o['protocol'] ?? '').toString();
    if (proto != 'vless' && proto != 'vmess' && proto != 'trojan') return null;
    final settings = (o['settings'] as Map?) ?? const {};
    final ss = (o['streamSettings'] as Map?) ?? const {};
    final net = (ss['network'] ?? 'tcp').toString();
    final sec = (ss['security'] ?? '').toString();
    final r = (ss['realitySettings'] as Map?) ??
        (ss['tlsSettings'] as Map?) ??
        const {};

    void addStream(Map<String, String> q) {
      q['type'] = net;
      if (sec.isNotEmpty) q['security'] = sec;
      if (r['serverName'] != null) q['sni'] = r['serverName'].toString();
      if (r['fingerprint'] != null) q['fp'] = r['fingerprint'].toString();
      if (r['publicKey'] != null) q['pbk'] = r['publicKey'].toString();
      if (r['shortId'] != null) q['sid'] = r['shortId'].toString();
      if (net == 'grpc') {
        final g = (ss['grpcSettings'] as Map?) ?? const {};
        if (g['serviceName'] != null) q['serviceName'] = g['serviceName'].toString();
      } else if (net == 'ws') {
        final w = (ss['wsSettings'] as Map?) ?? const {};
        if (w['path'] != null) q['path'] = w['path'].toString();
        final h = (w['headers'] as Map?)?['Host'];
        if (h != null) q['host'] = h.toString();
      }
    }

    String qstr(Map<String, String> q) =>
        q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final frag = Uri.encodeComponent(remark.isNotEmpty ? remark : proto);

    try {
      if (proto == 'vless' || proto == 'trojan') {
        final vnext =
            ((settings['vnext'] ?? settings['servers']) as List?) ?? const [];
        if (vnext.isEmpty) return null;
        final v = vnext.first as Map;
        final addr = v['address'];
        final port = v['port'];
        if (proto == 'vless') {
          final user = ((v['users'] as List?)?.first as Map?) ?? const {};
          final id = user['id'];
          if (id == null) return null;
          final q = <String, String>{'encryption': 'none'};
          final flow = (user['flow'] ?? '').toString();
          if (flow.isNotEmpty) q['flow'] = flow;
          addStream(q);
          return 'vless://$id@$addr:$port?${qstr(q)}#$frag';
        } else {
          final pass = v['password'];
          if (pass == null) return null;
          final q = <String, String>{};
          addStream(q);
          return 'trojan://$pass@$addr:$port?${qstr(q)}#$frag';
        }
      }
    } catch (_) {}
    return null;
  }

  List<String> _customRaws = const [];

  /// Добавляет сохранённые кастомные серверы к текущему списку (после синка
  /// с панелью, чтобы они не пропадали). Дубликаты по id отбрасываются.
  void _appendCustomServers() {
    if (_customRaws.isEmpty) return;
    final existing = servers.map((e) => e.id).toSet();
    for (final raw in _customRaws) {
      final s = SubscriptionParser.parseLink(raw);
      if (s != null && existing.add(s.id)) servers = [...servers, s];
    }
    _assignDisplayNames();
  }

  /// Проставляет человекочитаемые имена-страны. Если в одной стране несколько
  /// серверов — добавляет номер («Германия 1», «Германия 2»).
  void _assignDisplayNames() {
    // Оставляем ТОЛЬКО протоколы, которые умеет наше ядро (Xray): VLESS/VMess/
    // Trojan/SS. Hysteria2/TUIC/WireGuard приходят в подписке (для Happ/Hiddify),
    // но у нас не работают и раньше висели «мёртвыми» строками — убираем их,
    // чтобы в приложении не появлялись серверы, которых у нас нет.
    final usable = servers.where((s) => s.xraySupported).toList();
    if (usable.length != servers.length) servers = usable;
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
    // пользовательские имена переопределяют авто-название страны.
    if (_customNames.isNotEmpty) {
      for (final s in servers) {
        final cn = _customNames[s.id];
        if (cn != null && cn.isNotEmpty) s.displayName = cn;
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

  void setAutoRefreshSub(bool v) {
    autoRefreshSub = v;
    _storage.setBool('auto_refresh_sub', v);
    _rescheduleSubRefresh();
    notifyListeners();
  }

  void setAutoRefreshHours(int h) {
    autoRefreshHours = h;
    _storage.setInt('auto_refresh_hours', h);
    _rescheduleSubRefresh();
    notifyListeners();
  }

  /// Перезапускает таймер авто-обновления подписки. Работает, только если он
  /// включён И подписка привязана к ссылке (иначе нечего обновлять).
  void _rescheduleSubRefresh() {
    _subRefreshTimer?.cancel();
    _subRefreshTimer = null;
    final hasUrl = (_storage.subUrl ?? '').isNotEmpty;
    if (autoRefreshSub && hasUrl) {
      _subRefreshTimer = Timer.periodic(
        Duration(hours: autoRefreshHours.clamp(1, 24)),
        (_) => refreshSubscription(),
      );
    }
  }

  void setGlobeAnimations(bool v) {
    globeAnimations = v;
    _storage.setBool('globe_anim', v);
    notifyListeners();
  }

  void setLiteMode(bool v) {
    liteMode = v;
    _storage.setBool('lite_mode', v);
    notifyListeners();
  }

  void setLang(String v) {
    lang = v;
    L.current = v;
    _storage.setStr('lang', v);
    _assignDisplayNames(); // перевести названия стран/серверов на новый язык
    notifyListeners();
  }

  void setOnDemand(bool v) {
    onDemand = v;
    _storage.setBool('on_demand', v);
    notifyListeners();
    // «По требованию» = авто-восстановление упавшего туннеля. Сам по себе VPN
    // НЕ включает (это делает «Автоподключение»), поэтому здесь не коннектимся.
  }

  // ---- авто-VPN в незнакомых сетях ----
  void _initAutoWifi() {
    final g = AutoWifiGuard.instance;
    g.isTrusted = (ssid) => trustedSsids.contains(ssid);
    g.onUntrustedWifi = () {
      if (!autoWifiProtect) return;
      if (!isConnected && !_connecting && servers.isNotEmpty) {
        _log('Незнакомая Wi-Fi сеть — включаю VPN', LogKind.notice);
        connect();
      }
    };
    if (autoWifiProtect) g.start();
  }

  Future<bool> setAutoWifiProtect(bool v) async {
    if (v) {
      // читать SSID можно только с доступом к геолокации (требование Android)
      final ok = await AutoWifiGuard.instance.ensureLocationPermission();
      if (!ok) {
        lastError = 'Нужен доступ к геолокации для распознавания сетей';
        notifyListeners();
        return false;
      }
    }
    autoWifiProtect = v;
    _storage.setBool('auto_wifi', v);
    if (v) {
      AutoWifiGuard.instance.start();
    } else {
      AutoWifiGuard.instance.stop();
    }
    notifyListeners();
    return true;
  }

  /// Текущее имя Wi-Fi (для кнопки «добавить эту сеть» в списке доверенных).
  Future<String?> currentWifiSsid() => AutoWifiGuard.instance.currentSsid();

  /// Запросить доступ к геолокации (нужен для чтения имени Wi-Fi).
  Future<bool> ensureWifiPermission() =>
      AutoWifiGuard.instance.ensureLocationPermission();

  void addTrustedSsid(String ssid) {
    if (ssid.trim().isEmpty) return;
    trustedSsids = {...trustedSsids, ssid.trim()};
    _storage.setStr('trusted_ssids', trustedSsids.join('\n'));
    notifyListeners();
  }

  void removeTrustedSsid(String ssid) {
    trustedSsids = {...trustedSsids}..remove(ssid);
    _storage.setStr('trusted_ssids', trustedSsids.join('\n'));
    notifyListeners();
  }

  /// Вызывается при старте приложения. VPN поднимается сам ТОЛЬКО если включено
  /// «Автоподключение». Режим «По требованию» на запуск не влияет — он лишь
  /// возвращает связь, если она отвалилась во время сессии.
  void maybeAutoConnectOnLaunch() {
    if (autoConnect && !isConnected && !_connecting && servers.isNotEmpty) {
      connect();
    }
  }

  void setBypassRu(bool v) {
    bypassRu = v;
    _storage.setBool('bypass_ru', v);
    notifyListeners();
    _reconnectIfActive(); // применяем маршрутизацию сразу, без ручного реконнекта
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

  Timer? _switchDebounce;

  void setManualServer(String serverId) {
    manualServerId = serverId;
    _storage.manualServerId = serverId;
    // Ручной выбор = ручной режим.
    mode = GlobalMode.manual;
    _storage.globalMode = 'manual';
    notifyListeners(); // визуал (глобус/подсветка) меняется мгновенно
    // Если туннель поднят — переключаемся, но с ДЕБАУНСОМ: при быстром переборе
    // серверов не дёргаем ядро на каждый тап (иначе оно захлёбывается и коннект
    // тормозит). Ждём, пока выбор «устаканится» (450 мс), и поднимаем ТОЛЬКО
    // последний выбранный сервер.
    if (isConnected || _stage == VpnStage.connecting || telegramOnly) {
      _switchDebounce?.cancel();
      _switchDebounce = Timer(const Duration(milliseconds: 450), () {
        _reconnectTo();
      });
    }
  }

  /// Жёсткое переподключение к текущему выбранному серверу: полностью гасим
  /// туннель, ДОЖИДАЕМСЯ реального отключения ядра, затем поднимаем заново.
  /// Без ожидания нативный сервис не успевает пересоздать ядро с новым конфигом.
  bool _switching = false;
  Future<void> _reconnectTo() async {
    if (_switching) return;
    _switching = true;
    String? connectedId;
    try {
      telegramOnly = false;
      final srv = activeServer;
      if (srv == null) return;
      connectedId = srv.id;
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
    // Если пока переключались, пользователь выбрал ДРУГОЙ сервер — догоняем его.
    if (connectedId != manualServerId &&
        (isConnected || _stage == VpnStage.connecting)) {
      _reconnectTo();
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
    _storage.setBool('telegram_only', false); // обычное подключение = не free
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
    _stage = VpnStage.connecting;
    notifyListeners();
    // Чистый сброс ядра ПЕРЕД первой попыткой. На EMUI/Honor первый startV2Ray
    // после холодного старта часто срывается из-за недоподнятого прошлого ядра —
    // именно поэтому «переключение сервера» лечило проблему. Делаем этот сброс
    // сами, чтобы подключение срабатывало с первого раза.
    await _safeDisconnect();
    try {
      // Нужен ли сервер, на котором работают нейросети (умный доступ к ИИ).
      final wantAi = smartAi;
      // Сервер, где туннель ЖИВОЙ (интернет есть), но ИИ недоступен — запасной
      // вариант на случай, если ИИ не открывается нигде.
      VpnServer? internetOnly;

      // ДВА прохода по серверам: после долгого простоя/холодного старта первая
      // попытка ядра нередко срывается (сеть/DNS ещё не готовы). Мы НЕ доверяем
      // факту «startV2Ray не упал» — а РЕАЛЬНО проверяем связь через туннель и
      // при неудаче сами перебираем серверы и повторяем. Пользователь жмёт один
      // раз — остальное делаем прозрачно.
      for (var round = 1; round <= 2; round++) {
        // на 2-м проходе включаем фрагментацию TLS — если первый провал был из-за
        // DPI, режущего ClientHello, это часто помогает пробиться.
        _forceFragment = round >= 2;
        if (round >= 2) _log('Повтор с обходом DPI (фрагментация)…', LogKind.notice);
        for (final srv in candidates) {
          _log('Подключение к ${srv.flag} ${srv.title} '
              '(${srv.protocol.label})…', LogKind.connect);
          bool alive;
          try {
            alive = await _tryConnect(srv);
          } catch (e) {
            _log('${srv.title}: $e', LogKind.error);
            await _safeDisconnect();
            continue;
          }
          if (!alive) {
            _log('${srv.title}: туннель не отвечает, пробую следующий',
                LogKind.notice);
            await _safeDisconnect();
            continue;
          }
          // Туннель РЕАЛЬНО работает (проверено запросом через него).
          if (wantAi && !await _aiReachable()) {
            internetOnly ??= srv; // интернет есть — запомним на крайний случай
            _log('${srv.title}: нейросети недоступны здесь, ищу другой сервер',
                LogKind.notice);
            await _safeDisconnect();
            continue;
          }
          _finishConnect(srv, aiOk: wantAi);
          return;
        }
      }

      // Сервер с ИИ не нашёлся, но есть рабочий интернет — подключаемся к нему
      // (доступ в сеть важнее, чем открытие нейросетей).
      if (internetOnly != null) {
        try {
          if (await _tryConnect(internetOnly)) {
            _finishConnect(internetOnly, aiOk: false);
            _notify('Подключено. Нейросети на этом сервере могут не открываться');
            return;
          }
        } catch (_) {}
      }

      _stage = VpnStage.disconnected;
      lastError = 'Не удалось подключиться — проверь интернет и подписку';
      _notify(lastError!);
      await _safeDisconnect();
    } finally {
      _connecting = false;
      _forceFragment = false; // сбрасываем анти-DPI флаг до следующего connect
      notifyListeners();
    }
  }

  /// Фиксирует успешное подключение к [srv]. Форсирует стадию «connected», даже
  /// если нативный статус на EMUI/MIUI не пришёл — связь уже проверена пробой.
  void _finishConnect(VpnServer srv, {required bool aiOk}) {
    manualServerId = srv.id; // фиксируем рабочий сервер
    _storage.manualServerId = srv.id;
    _storage.setBool('was_connected', true); // для мгновенного восстановления
    if (_stage != VpnStage.connected) {
      _stage = VpnStage.connected;
      _startSession();
    }
    _notify('Подключено: ${srv.flag} ${srv.countryName}'
        '${aiOk ? ' · нейросети работают' : ''}');
    notifyListeners();
    _reportStreak(); // отмечаем день серии (огонёк) на сервере
  }

  // ---------------- Стрик использования («огонёк», как в TikTok) ----------------
  int streak = 0; // текущая серия дней подряд
  int streakBest = 0; // рекорд
  int streakFreezes = 0; // заморозки в запасе
  int streakNextMilestone = 0; // до какой вехи тянемся
  Map<int, int> streakRewards = const {}; // веха → бонус-дни (для экрана наград)
  int _lastSessionMinutes = 0; // длительность прошлой сессии (для заработка заморозок)

  // всплывающее празднование награды (огонёк) — читает главный экран
  int celebrateMilestone = 0; // веха, которую только что взяли (0 = нет)
  int celebrateRewardDays = 0; // сколько дней начислено

  void clearCelebration() {
    celebrateMilestone = 0;
    celebrateRewardDays = 0;
    notifyListeners();
  }

  /// Отмечает день использования VPN на сервере (панель — источник правды,
  /// накрутку сменой даты не пройти). Награда начисляется к подписке сервером
  /// и прилетает уведомлением из бота. Здесь — обновляем счётчики и, если взяли
  /// веху, показываем красивую анимацию огонька.
  Future<void> _reportStreak() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) return;
    try {
      final r = await http
          .post(Uri.parse('${Brand.panelBase}/api/app/streak'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'tg_id': tg, 'minutes': _lastSessionMinutes}))
          .timeout(const Duration(seconds: 10));
      _lastSessionMinutes = 0; // учли — обнуляем
      if (r.statusCode != 200) return;
      _applyStreak(jsonDecode(r.body) as Map<String, dynamic>);
      final awarded = (streakData['awarded_days'] as int?) ?? 0;
      if (awarded > 0) {
        celebrateMilestone = (streakData['milestone'] as int?) ?? streak;
        celebrateRewardDays = awarded;
        if (vibrationEnabled) HapticFeedback.heavyImpact();
      }
      notifyListeners();
    } catch (_) {}
  }

  Map<String, dynamic> streakData = const {};

  void _applyStreak(Map<String, dynamic> d) {
    streakData = d;
    streak = (d['streak'] as int?) ?? streak;
    streakBest = (d['best'] as int?) ?? streakBest;
    streakFreezes = (d['freezes'] as int?) ?? streakFreezes;
    streakNextMilestone = (d['next_milestone'] as int?) ?? 0;
    final rw = d['rewards'];
    if (rw is Map) {
      streakRewards = {
        for (final e in rw.entries)
          int.tryParse(e.key.toString()) ?? 0: (e.value as num).toInt()
      }..removeWhere((k, _) => k == 0);
    }
  }

  String profileUsername = ''; // ник из Telegram (подтягивается к профилю)

  /// Тянет профиль (ник + стрик) для экрана профиля (без отметки дня).
  Future<void> loadStreak() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse('${Brand.panelBase}/api/app/profile?tg_id=$tg'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      profileUsername = (d['username'] ?? '').toString();
      _applyStreak(d);
      notifyListeners();
    } catch (_) {}
  }

  /// Аккуратно опускает туннель между попытками и даёт ОС время снять
  /// VPN-интерфейс (иначе следующий startV2Ray стартует поверх недоснятого).
  Future<void> _safeDisconnect() async {
    try {
      await vpn.disconnect();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Пытается поднять туннель к [srv] И проверяет, что через него реально идёт
  /// трафик. Возвращает true ТОЛЬКО при подтверждённой связи — это и есть
  /// защита от «показывает подключено, а интернета нет».
  Future<bool> _tryConnect(VpnServer srv) async {
    // бросит на неподдерживаемом протоколе → обрабатывается выше
    await vpn.connect(srv, rules: rules, net: net, blockedApps: blockedApps);
    return _verifyTunnel();
  }

  /// Проверяет, что туннель РЕАЛЬНО несёт трафик, в течение ~14 с.
  ///
  /// Раньше проверка была только app-side HTTP-запросом (204). Но пока ОС ещё не
  /// применила VPN-маршрут, такой запрос проходит НАПРЯМУЮ и возвращает 204 —
  /// ложное «подключено» на мёртвом туннеле (тот самый баг «подключается только
  /// со 2-й попытки»). Теперь основная проверка — задержка ЧЕРЕЗ ядро Xray
  /// (`vpn.connectedDelay()`): она валидна, только если туннель реально работает.
  /// HTTP-проба оставлена как запасная (на случай, если ядро не отдаёт задержку).
  Future<bool> _verifyTunnel() async {
    const endpoints = [
      'https://www.gstatic.com/generate_204',
      'https://cp.cloudflare.com/generate_204',
      'https://www.google.com/generate_204',
    ];
    // Ждём, пока ОС применит VPN-маршрут (пред-establish окно ~1-2 с — именно в
    // нём HTTP мог уйти напрямую и дать ложный успех). После этой паузы весь
    // трафик приложения уже идёт в tun, поэтому ответу 204 можно верить.
    await Future.delayed(const Duration(milliseconds: 1800));
    final deadline = DateTime.now().add(const Duration(seconds: 14));
    var i = 0;
    while (DateTime.now().isBefore(deadline)) {
      // Быстрый бонус: задержка через ядро. На части прошивок (EMUI/Honor)
      // ответ ядра приходит broadcast'ом, который система режет в фоне — тогда
      // тут будет таймаут, поэтому держим его КОРОТКИМ и не полагаемся на него.
      try {
        final d = await vpn.connectedDelay().timeout(const Duration(seconds: 2));
        if (d >= 0) return true;
      } catch (_) {}
      // Основная проверка: запрос через уже поднятый tun. Маршрут применён (мы
      // подождали выше), поэтому 204/200 = туннель реально несёт трафик.
      try {
        final r = await http
            .get(Uri.parse(endpoints[i++ % endpoints.length]))
            .timeout(const Duration(seconds: 4));
        if (r.statusCode == 204 || r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Проверяет, открываются ли нейросети через текущий туннель. В некоторых
  /// странах (напр. IP Нидерландов) Gemini/OpenAI недоступны, тогда «умный
  /// доступ к ИИ» перебирает серверы, пока не найдёт тот, где ИИ работает.
  /// Любой HTTP-ответ (даже 403/404) = TLS прошёл = сервис ДОСТУПЕН.
  Future<bool> _aiReachable() async {
    const endpoints = [
      'https://generativelanguage.googleapis.com/',
      'https://api.openai.com/',
    ];
    for (final e in endpoints) {
      try {
        final r =
            await http.get(Uri.parse(e)).timeout(const Duration(seconds: 5));
        if (r.statusCode > 0) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Выбирает реально отвечающий сервер: быстрый TCP-замер всех совместимых,
  /// берём с минимальным пингом (отсекаем «мёртвые»). Так бесплатный режим и
  /// авто-режим подсовывают РАБОЧИЙ конфиг, а не жёстко первый по списку.
  Future<VpnServer?> _bestReachableServer() async {
    final list = servers.where((s) => s.xraySupported).toList();
    if (list.isEmpty) return servers.isNotEmpty ? servers.first : null;
    final pings = await Future.wait(list.map((s) async {
      final ms = await tcpPing(s.address, s.port)
          .timeout(const Duration(seconds: 3), onTimeout: () => -1);
      s.pingMs = ms;
      return ms;
    }));
    VpnServer? best;
    var bestPing = 1 << 30;
    for (var i = 0; i < list.length; i++) {
      final p = pings[i];
      if (p > 0 && p < bestPing) {
        bestPing = p;
        best = list[i];
      }
    }
    return best ?? list.first;
  }

  /// Бесплатный режим (до оплаты): поднимает РЕАЛЬНЫЙ рабочий сервер и пускает
  /// через туннель ТОЛЬКО Telegram. Навигацию не блокируем — подключение
  /// устанавливается, экран-инструкция открывается сразу. Возвращает true, если
  /// подключение стартовало.
  Future<bool> connectTelegramOnly() async {
    // Нужен хотя бы один настоящий сервер — берём из панели (тот же /vsub).
    if (servers.where((s) => s.xraySupported).isEmpty) {
      try {
        final raw = await _api.fetchSubscription(Brand.panelSub);
        final parsed = SubscriptionParser.parseContent(raw);
        if (parsed.isNotEmpty) {
          servers = parsed;
          _assignDisplayNames();
          await _storage.saveConfigsBlob(raw);
        }
      } catch (_) {}
    }
    final srv = await _bestReachableServer();
    if (srv == null) {
      lastError = 'Не удалось получить сервер — попробуй позже или возьми '
          'подписку в боте';
      _notify(lastError!);
      notifyListeners();
      return false;
    }
    final ok = await vpn.requestPermission();
    if (!ok) {
      lastError = 'Нет разрешения на VPN';
      notifyListeners();
      return false;
    }
    telegramOnly = true;
    _storage.setBool('telegram_only', true); // переживает перезапуск приложения
    manualServerId = srv.id;
    _stage = VpnStage.connecting;
    notifyListeners();
    _log('Бесплатный режим (только Telegram) → ${srv.flag} ${srv.title}',
        LogKind.connect);
    await _safeDisconnect();
    // «Только Telegram» реализовано РОУТИНГОМ Xray (net.telegramOnly=true, см.
    // xray_config): к серверу идёт только трафик Telegram, всё остальное —
    // напрямую. Это надёжно и не зависит от списка установленных приложений
    // (blockedApps раньше при пустом списке пропускал ВЕСЬ трафик в туннель).
    vpn.connect(srv, rules: rules, net: net, blockedApps: const []).then((_) {
      _notify('🆓 Бесплатный VPN включён — работает только Telegram');
    }).catchError((e) {
      _log('Бесплатный режим: $e', LogKind.error);
    });
    return true;
  }

  Future<void> disconnect() async {
    _log('Отключено', LogKind.disconnect);
    _storage.setBool('was_connected', false); // осознанное отключение
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
        // «Прокси»-пинг = TCP+TLS-хендшейк к Reality-порту: быстро (~100-300 мс)
        // и точнее чистого TCP (учитывает TLS). Медленный getServerDelay ядра
        // (~10 с) не используем — плагин грузит geoip на каждый замер.
        v = await tlsPing(s.address, s.port)
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
      } else {
        v = await tcpPing(s.address, s.port);
      }
      if (isConnected && v > 0 && v < 10) v = -1; // артефакт локального сокета туннеля
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
    // Полный сброс статуса подписки и серии — иначе на экране «висит» карточка
    // «Подписка активна» от прошлого аккаунта (в т.ч. админ-разблокировка).
    subActive = false;
    subUntil = null;
    subLoaded = true;
    streak = 0;
    streakBest = 0;
    profileUsername = '';
    logs.clear();
    notifyListeners();
    _pushWidget();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _aiTimer?.cancel();
    _subRefreshTimer?.cancel();
    notice.dispose();
    vpn.dispose();
    super.dispose();
  }
}
