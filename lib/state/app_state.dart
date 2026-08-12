/// Центральное состояние приложения (ChangeNotifier + provider).
///
/// Связывает хранилище, бэкенд, парсер и VPN-ядро. Экраны читают это состояние
/// и дёргают его методы — вся логика здесь, UI остаётся «тонким».
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../brand.dart';
import '../models/app_rule.dart';
import '../models/connection_status.dart';
import '../models/log_entry.dart';
import '../models/support_message.dart';
import '../l10n.dart';
import '../services/live_activity.dart';
import '../models/vpn_server.dart';
import '../services/auto_wifi_guard.dart';
import '../services/backend_api.dart';
import '../services/home_widget_sync.dart';
import '../services/ping.dart';
import '../services/vpn_status_probe.dart';
import '../theme/app_fonts.dart';
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

/// Уведомление для плашки сверху: текст плюс характер события.
///
/// Отдельный тип, а не пара строк: цвет и значок плашки выбираются по этому
/// признаку, и держать его рядом с текстом надёжнее, чем угадывать по словам.
class AppNotice {
  final String text;
  final bool error;
  final bool success;

  const AppNotice(this.text, {this.error = false, this.success = false});
}

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
      _watchOneWayTraffic(now);
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
    // Имя для виджета: берём первое НЕПУСТОЕ. Раньше стояло `a?.title ?? …` —
    // оператор ?? ловит только null, поэтому пустой заголовок уезжал в виджет
    // как есть, и в «пилюле» рядом с флагом было пустое место.
    final name = [
          a?.title,
          a?.countryName,
          a?.address,
        ].firstWhere((e) => e != null && e.trim().isNotEmpty,
            orElse: () => null) ??
        L.t('wdg_no_server');
    HomeWidgetSync.push(
      connected: isConnected,
      countryCode: a?.countryCode ?? '',
      server: name,
      host: a?.address ?? '',
      port: a?.port ?? 0,
      pingType: pingType,
      pingMs: a?.pingMs ?? -1,
      telegramOnly: telegramOnly,
    );

    // То же состояние — в живое событие iOS (Dynamic Island и экран
    // блокировки). Место общее с домашним виджетом намеренно: оба показывают
    // одно и то же, и разойтись они не должны.
    LiveActivity.push(
      connected: isConnected,
      status: isConnected ? L.t('protected') : L.t('disconnected'),
      server: name,
      countryCode: a?.countryCode ?? '',
      ping: (telegramOnly || (a?.pingMs ?? -1) <= 0) ? '' : '${a!.pingMs} ms',
      up: _speedLabel(speedUpKbps),
      down: _speedLabel(speedDownKbps),
      since: _sessionStart,
    );
  }

  /// Скорость строкой. Считаем здесь, а не в самом событии: у расширения нет
  /// доступа к переводам, а правила округления обязаны совпадать с теми, что
  /// человек видит в приложении.
  String _speedLabel(double kbps) => kbps >= 1024
      ? '${(kbps / 1024).toStringAsFixed(1)} ${L.t('unit_mbps')}'
      : '${kbps.toStringAsFixed(0)} ${L.t('unit_kbps')}';

  // ---- состояние ----

  /// Список серверов.
  ///
  /// Свойство, а не поле: при КАЖДОМ присвоении заново применяется порядок,
  /// который выставил человек. Присвоений по коду восемнадцать — обновление
  /// подписки, импорт, добавление своих серверов, — и раньше порядок
  /// восстанавливался лишь в одном из них. Из-за этого расстановка,
  /// выстраданная перетаскиванием, слетала при первом же обновлении подписки.
  List<VpnServer> get servers => _servers;
  set servers(List<VpnServer> v) {
    _servers = v;
    _applyServerOrder();
  }

  List<VpnServer> _servers = [];

  /// Пользовательский порядок серверов (список id). Пусто = порядок подписки.
  List<String> _serverOrder = [];

  /// Применяет сохранённый порядок к [servers]: известные — по порядку,
  /// новые (которых нет в порядке) — в конец, сохраняя порядок подписки.
  void _applyServerOrder() {
    if (_serverOrder.isEmpty) return;
    final idx = {
      for (var i = 0; i < _serverOrder.length; i++) _serverOrder[i]: i
    };
    _servers
        .sort((a, b) => (idx[a.id] ?? 1 << 30).compareTo(idx[b.id] ?? 1 << 30));
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

  /// Выбранный шрифт интерфейса (ключ из AppFonts).
  String fontKey = AppFonts.defaultKey;

  void setFontKey(String v) {
    if (fontKey == v) return;
    fontKey = v;
    _storage.setStr('font_key', v);
    notifyListeners();
  }


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
  bool splitThroughVpn =
      false; // true=«Через VPN» (выбранные→VPN, остальные напрямую)
  //                                false=«В обход VPN» (выбранные напрямую, остальные→VPN)
  Set<String> splitApps = {}; // выбранные package name
  /// Все установленные приложения — нужны режиму «через VPN»: там в туннель
  /// пускаются только выбранные, а значит остальные надо перечислить поимённо.
  ///
  /// Список ХРАНИТСЯ между запусками. Раньше он заполнялся только при открытии
  /// экрана «По приложениям»: после перезапуска он был пуст, список исключений
  /// получался пустым — и весь трафик молча шёл в туннель, хотя человек выбрал
  /// всего пару приложений.
  Set<String> allPackages = {};

  void setAllPackages(Set<String> packages) {
    if (packages.isEmpty) return;
    allPackages = packages;
    _storage.setStr('all_packages', packages.join('\n'));
  }
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
  bool smartAi =
      true; // умный доступ к ИИ (ChatGPT/Gemini/Claude через туннель)
  bool mux = false; // мультиплексирование: много запросов по одному соединению
  bool lanDirect = true; // локальная сеть (принтер, роутер) мимо туннеля

  void setMux(bool v) {
    mux = v;
    _storage.setBool('mux', v);
    notifyListeners();
    if (isConnected) _reconnectTo();
  }

  void setLanDirect(bool v) {
    lanDirect = v;
    _storage.setBool('lan_direct', v);
    notifyListeners();
    if (isConnected) _reconnectTo();
  }

  /// Собранные сетевые опции для передачи в ядро при connect.
  NetOptions get net => NetOptions(
        dns: customDns.trim().isEmpty
            ? const []
            : customDns
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
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
        mux: mux,
        lanDirect: lanDirect,
      );

  bool adBlock = false; // блокировка рекламы/трекеров в туннеле
  void setAdBlock(bool v) {
    adBlock = v;
    _storage.setBool('ad_block', v);
    notifyListeners();
    if (isConnected) _reconnectTo();
  }

  bool _forceFragment =
      false; // авто-фрагментация на повторной попытке (анти-DPI)

  // Динамические списки маршрутизации (тянутся из панели, кэшируются локально).
  List<String> _aiDomains = const [];
  List<String> _ruDomains = const [];
  List<String> _adDomains = const [];

  void _loadCachedRouting() {
    final ai = _storage.getStr('routing_ai', def: '');
    final ru = _storage.getStr('routing_ru', def: '');
    final ad = _storage.getStr('routing_ad', def: '');
    if (ai.isNotEmpty) {
      _aiDomains = ai.split('\n').where((e) => e.isNotEmpty).toList();
    }
    if (ru.isNotEmpty) {
      _ruDomains = ru.split('\n').where((e) => e.isNotEmpty).toList();
    }
    if (ad.isNotEmpty) {
      _adDomains = ad.split('\n').where((e) => e.isNotEmpty).toList();
    }
  }

  /// Тянет актуальные списки маршрутизации из панели (ИИ + РФ-домены). При смене
  /// CDN у OpenAI/Anthropic достаточно поправить список в панели — приложение
  /// подхватит без обновления. Кэшируется, чтобы работать оффлайн.
  Future<void> loadRouting() async {
    try {
      final r = await HostHealth.get(
          Uri.parse('${Brand.panelBase}/api/app/routing'),
          timeout: const Duration(seconds: 6));
      if (r == null || r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final ai =
          (d['ai_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final ru = (d['ru_direct_domains'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final ad =
          (d['ad_domains'] as List?)?.map((e) => e.toString()).toList() ?? [];
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

  /// Транзиентное уведомление для плашки сверху. UI слушает и сбрасывает.
  ///
  /// Вместе с текстом несём и характер события: успех и ошибку человек должен
  /// различать, не вчитываясь. Раньше здесь была голая строка, и «список
  /// обновлён» с «подписка не найдена» выглядели одинаково.
  final ValueNotifier<AppNotice?> notice = ValueNotifier<AppNotice?>(null);

  VpnStage get stage => _stage;
  bool get isConnected => _stage == VpnStage.connected;
  bool get hasServers => servers.isNotEmpty;

  /// Перечитать настройки из хранилища в память.
  ///
  /// Нужен после восстановления из резервной копии и после сброса: без этого
  /// новые значения лежали бы в хранилище, а приложение продолжало работать со
  /// старыми до перезапуска — человек решил бы, что восстановление не сработало.
  Future<void> reloadSettings() async {
    await bootstrap();
    notifyListeners();
  }

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
    // Доступ, выданный при импорте подписки, сохраняется (замки открыты), НО
    // только пока не истёк известный срок: иначе после окончания подписки
    // офлайн-запуск возвращал полный доступ по «вечному» флагу.
    if (_storage.getBool('access_granted', def: false)) {
      final iso = _storage.getStr('sub_until_cache', def: '');
      final until = iso.isEmpty ? null : DateTime.tryParse(iso);
      if (until != null && until.isBefore(DateTime.now())) {
        _storage.setBool('access_granted', false);
        _storage.setBool('sub_active_cache', false);
      } else {
        subActive = true;
        subLoaded = true;
      }
    }
    autoRefreshSub = _storage.getBool('auto_refresh_sub', def: false);
    autoRefreshHours = _storage.getInt('auto_refresh_hours', def: 6);
    onDemand = _storage.getBool('on_demand', def: false);
    adBlock = _storage.getBool('ad_block', def: false);
    liteMode = _storage.getBool('lite_mode', def: false);
    compactServers = _storage.getBool('compact_servers', def: false);
    fontKey = _storage.getStr('font_key', def: AppFonts.defaultKey);
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
    final pkgs = _storage.getStr('all_packages', def: '');
    if (pkgs.isNotEmpty) {
      allPackages = pkgs.split('\n').where((e) => e.isNotEmpty).toSet();
    }
    autoWifiProtect = _storage.getBool('auto_wifi', def: false);
    final tsRaw = _storage.getStr('trusted_ssids', def: '');
    trustedSsids = tsRaw.isEmpty ? {} : tsRaw.split('\n').toSet();
    _initAutoWifi();
    final cr = _storage.getStr('custom_raws', def: '');
    _customRaws = cr.isEmpty
        ? const []
        : cr.split('\n').where((e) => e.isNotEmpty).toList();
    final fr = _storage.getStr('foreign_raws', def: '');
    _foreignRaws = fr.isEmpty
        ? const []
        : fr.split('\n').where((e) => e.isNotEmpty).toList();
    await _loadForeignBodies();
    _loadForeignInfo();
    final fu = _storage.getStr('foreign_until', def: '');
    if (fu.isNotEmpty) {
      final m = <String, DateTime>{};
      for (final line in fu.split('\n')) {
        final parts = line.split('\t');
        if (parts.length != 2) continue;
        final ts = int.tryParse(parts[1]);
        if (ts != null) m[parts[0]] = DateTime.fromMillisecondsSinceEpoch(ts);
      }
      foreignUntil = m;
    }
    final fs = _storage.getStr('foreign_subs', def: '');
    foreignSubUrls = fs.isEmpty
        ? const []
        : fs.split('\n').where((e) => e.isNotEmpty).toList();
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
    mux = _storage.getBool('mux', def: false);
    lanDirect = _storage.getBool('lan_direct', def: true);
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
        : (PlatformDispatcher.instance.locale.languageCode == 'en'
            ? 'en'
            : 'ru');
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
    _appendForeignServers();
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
    // Мгновенно показываем дату подписки из кэша, затем обновляем в фоне.
    _loadSubCache();
    refreshSubStatus();
    _refreshExpiryFromPersonalLink(); // без TG — подтягиваем срок из личной ссылки
    // Сразу измерим пинги (в фоне, TCP) — чтобы значения были видны при входе,
    // а не появлялись только через 30 сек на первом авто-тике.
    if (servers.isNotEmpty) _pingAllSilent(background: true);
    // Источник серверов — админ-панель. Если ссылка не привязана, привязываем
    // панельную (/vsub) и подтягиваем серверы в фоне: добавил сервер в панели →
    // он появляется в приложении и на глобусе.
    _syncFromPanel();
    _initConnectivity(); // следим за наличием интернета у пользователя
    vpn.warmUp(); // прогреваем ядро заранее — чтобы первое подключение
    // за день срабатывало сразу, а не со второй попытки
    _startSubGuard(); // применяем окончание подписки и во время сессии
  }

  // ---- наличие интернета (для баннера «VPN не заработает без сети») ----
  bool online = true; // есть ли у телефона хоть какая-то сеть (Wi-Fi/моб.)
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  void _initConnectivity() {
    // Определение сети — вспомогательная вещь: она подсвечивает «нет
    // интернета» и не более. Если канал недоступен (редкие прошивки, ранний
    // старт), приложение обязано продолжить работать, а не падать на старте.
    try {
      final conn = Connectivity();
      _connSub = conn.onConnectivityChanged
          .handleError((_) {})
          .listen(_onConnectivity);
      conn.checkConnectivity().then(_onConnectivity).catchError((_) {
        online = true; // не знаем — считаем, что сеть есть
      });
    } catch (_) {
      online = true;
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    // Сеть есть, если присутствует любой транспорт, кроме «none».
    final has = results.any((r) => r != ConnectivityResult.none);
    if (has != online) {
      online = has;
      notifyListeners();
    }
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
    _storage.subUrl = _subSource;
    final url = _subSource;
    try {
      final raw = await _api.fetchSubscription(url);
      final parsed = SubscriptionParser.parseContent(raw);
      if (parsed.isNotEmpty) {
        servers = parsed;
        _assignDisplayNames();
        _appendCustomServers(); // не теряем свои серверы после синка
        _appendForeignServers();
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
  void _notify(String text, {bool error = false, bool success = false}) {
    _log(text, LogKind.notice);
    if (notificationsEnabled) {
      notice.value = AppNotice(text, error: error, success: success);
    }
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

  // --- «отдаём, а получаем ноль» ---
  // Самое коварное состояние: приложение показывает «Подключено», счётчик
  // отданного растёт (запросы уходят), а скачано ноль. Формально туннель есть,
  // фактически интернета нет. Раньше приложение молчало об этом сколько угодно
  // долго. Теперь замечаем сами и уходим на рабочий сервер.
  DateTime? _oneWaySince;
  int _oneWayDownMark = 0;

  /// Сколько терпим «отдача идёт, приём молчит» до настоящей пробы связи.
  /// Отправка файла или звонок выглядят ровно так же — короткий порог рвал
  /// соединение посреди обычной работы.
  static const oneWayGraceSeconds = 45;

  bool _oneWayChecking = false;

  void _watchOneWayTraffic(DateTime now) {
    if (!isConnected || _connecting || _switching || _oneWayChecking) {
      if (!isConnected) _oneWaySince = null;
      return;
    }
    // Скачанное растёт — всё в порядке.
    if (bytesDown > _oneWayDownMark + 2048) {
      _oneWayDownMark = bytesDown;
      _oneWaySince = null;
      return;
    }
    // Наружу ничего не уходит — просто тишина, а не поломка.
    if (bytesUp < 8 * 1024) return;
    _oneWaySince ??= now;
    // 45 секунд вместо прежних 12. Отдача при почти молчащем приёме — это
    // НОРМАЛЬНАЯ картина: отправка фото или видео, голосовой звонок, выгрузка
    // в облако. На 12 секундах такое срабатывало посреди обычной работы, и
    // соединение обрывалось «просто так».
    if (now.difference(_oneWaySince!).inSeconds < oneWayGraceSeconds) {
      return;
    }
    _oneWaySince = null;

    // И даже теперь сервер по одной статистике мёртвым не объявляем: сначала
    // настоящая проба связи. Раньше решение принималось только по счётчикам —
    // отсюда и ложные переключения.
    _oneWayChecking = true;
    () async {
      try {
        if (await _tunnelAlive()) {
          _oneWayDownMark = bytesDown;
          return; // связь есть, тревога ложная
        }
        final srv = activeServer;
        if (srv == null || !isConnected || _switching) return;
        _log('${srv.title}: трафик уходит, но не возвращается', LogKind.error);
        srv.unreachable = true;
        await _fallbackFromDead(srv);
      } finally {
        _oneWayChecking = false;
      }
    }();
  }
  double speedDownKbps = 0;
  double speedUpKbps = 0;
  DateTime? _lastTrafficAt; // для расчёта скорости из прироста байтов
  final List<double> speedHistory = []; // последние ~40 точек (КБ/с, принято)
  final List<double> speedHistoryUp = []; // последние ~40 точек (КБ/с, отдано)

  Duration get sessionDuration => _sessionStart == null
      ? Duration.zero
      : DateTime.now().difference(_sessionStart!);

  void _startSession() {
    _sessionStart = DateTime.now();
    bytesDown = 0;
    bytesUp = 0;
    _oneWayDownMark = 0;
    _oneWaySince = null;
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
  /// Когда приложение в последний раз само пересобирало соединение.
  ///
  /// Один на всех: и сторож туннеля, и авто-выбор лучшего сервера смотрят
  /// сюда. Раньше у каждого был свой счётчик по минуте, и они переключали по
  /// очереди — соединение рвалось каждые тридцать секунд.
  DateTime? _lastAutoReconnect;

  /// Не пора ли оставить соединение в покое.
  bool get _reconnectedRecently =>
      _lastAutoReconnect != null &&
      DateTime.now().difference(_lastAutoReconnect!).inSeconds < 60;

  // --- окна для проверок ---
  //
  // Согласованность двух сторожей проверяется тестом: разъехавшись, они
  // рвали соединение каждые полминуты, а по коду это незаметно.
  @visibleForTesting
  bool get debugReconnectedRecently => _reconnectedRecently;

  @visibleForTesting
  void debugMarkReconnected() => _lastAutoReconnect = DateTime.now();

  @visibleForTesting
  int get debugHealthFails => _healthFails;

  @visibleForTesting
  set debugHealthFails(int v) => _healthFails = v;

  /// Тик сторожа, пришедшийся на замер списка: вердикта нет, память цела.
  @visibleForTesting
  void debugNoteSweepTick() => _wdLastBytes = bytesDown;

  /// Как часто проверяем, жив ли туннель.
  ///
  /// 15 секунд — компромисс: чаще смысла нет (проба сама занимает секунды и
  /// это лишний трафик), реже — человек успевает заметить, что «интернет
  /// пропал», раньше приложения.
  static const healthEvery = Duration(seconds: 15);

  /// Сколько проб подряд должно провалиться до переключения.
  ///
  /// Две — то есть примерно 30 секунд реальной недоступности. Одной мало:
  /// разовая неудачная проба бывает на переключении вышки или при спящем
  /// Wi-Fi, и рвать рабочее соединение из-за неё нельзя.
  static const healthFailsToSwitch = 2;

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _healthFails = 0;
    _wdLastBytes = bytesDown;
    _watchdogTimer = Timer.periodic(healthEvery, (_) async {
      if (!isConnected || _switching || _connecting) return;
      // Во время замера списка вердикт не выносим: замер идёт через ядро и
      // занимает его целиком, проба не успеет и соврёт. Но и накопленное НЕ
      // ЗАБЫВАЕМ — обнуление счётчика здесь означало бы, что при непрерывных
      // замерах мёртвый туннель не заметит никто. Ложных неудач не возникнет:
      // проба в это время просто не берётся.
      if (pingSweepRunning) {
        _wdLastBytes = bytesDown;
        return;
      }

      // 1) Трафик идёт — туннель точно жив. Это главная защита: пока человек
      //    чем-то пользуется, ничего не трогаем.
      if (bytesDown > _wdLastBytes) {
        _wdLastBytes = bytesDown;
        _healthFails = 0;
        return;
      }

      // 2) Трафика нет — это может быть и простой. Проверяем настоящей пробой.
      final ok = await _tunnelAlive();
      _wdLastBytes = bytesDown;
      if (ok) {
        _healthFails = 0;
        return;
      }
      _healthFails++;
      if (_healthFails < healthFailsToSwitch) return;

      // 3) Туннель действительно молчит. Кулдаун защищает от петли, если
      //    недоступна сама сеть телефона, а не сервер.
      if (_reconnectedRecently) return;
      _healthFails = 0;
      _lastAutoReconnect = DateTime.now();

      final cur = activeServer;
      _log('Туннель не отвечает ${healthEvery.inSeconds * healthFailsToSwitch}'
          ' с — переключаюсь', LogKind.notice);

      // В авто-режиме уходим на ЛУЧШИЙ из оставшихся, а не переподключаемся к
      // тому же серверу: раз он молчит, повторная попытка обычно бесполезна.
      // В ручном режиме сервер выбрал человек — его выбор не подменяем,
      // просто пробуем поднять соединение заново.
      if (mode == GlobalMode.ai && cur != null) {
        cur.unreachable = true;
        final best = _bestServer();
        if (best.id != cur.id) {
          _setAutoServer(best.id);
          await _reconnectTo();
          return;
        }
      }
      await _reconnectTo();
    });
  }

  /// Лёгкая проба живости туннеля с одним повтором (меньше ложных срабатываний).
  Future<bool> _tunnelAlive() async {
    // Одна короткая проба. Повторов здесь больше нет: сторож и так требует
    // ДВУХ проваленных проверок подряд, а прежние ретраи с паузами растягивали
    // одну проверку почти на весь цикл сторожа.
    try {
      final r = await http
          .get(Uri.parse(kProbeUrl))
          .timeout(const Duration(seconds: 4));
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
    // копим минуты сессии — из них сервер начисляет «заморозки» серии (≥25 ч/нед)
    _lastSessionMinutes += dur.inMinutes;
    if (_sessionCountry.isNotEmpty) {
      final h = dur.inHours, m = dur.inMinutes % 60, s = dur.inSeconds % 60;
      final t = h > 0 ? '$h ч $m мин' : (m > 0 ? '$m мин $s с' : '$s с');
      _log('Отключено от: $_sessionCountry · время: $t', LogKind.notice);
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
  Map<String, dynamic> _allTime = {
    'down': 0,
    'up': 0,
    'countries': {},
    'servers': {},
    'days': {}
  };
  String _sessionCountry = '';
  String _sessionCC = ''; // код страны текущей сессии (ключ статистики)
  String _sessionServerId = ''; // id сервера текущей сессии (для по-серверной)
  String _sessionServerName = '';

  int get allTimeDown => (_allTime['down'] as num).toInt();
  int get allTimeUp => (_allTime['up'] as num).toInt();

  /// Топ стран по трафику: список (код страны, байты), по убыванию.
  /// Ключ — двухбуквенный код (DE/NL/FI…), имя берётся через [countryNameOf].
  List<MapEntry<String, int>> get topCountries {
    final m = (_allTime['countries'] as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toInt()));
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
        byName[name] =
            (byName[name] ?? 0) + ((rec['down'] ?? 0) as num).toInt();
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
      out.add(
          MapEntry('${d.day}.${d.month}', ((days[key] ?? 0) as num).toInt()));
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
      await http
          .post(
            Uri.parse('${Brand.panelBase}/api/app/support'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'tg_id': tg, 'text': t}),
          )
          .timeout(const Duration(seconds: 8));
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
          ok
              ? '✅ Файл отправлен — мы его получили 💙'
              : 'Не удалось отправить файл. Попробуй ещё раз.',
          fromUser: false));
      notifyListeners();
      return ok;
    } catch (_) {
      supportChat.add(SupportMessage(
          'Не удалось отправить файл — проверь интернет.',
          fromUser: false));
      notifyListeners();
      return false;
    }
  }

  /// Подтягивает переписку поддержки из панели (ответы админа).
  Future<void> loadSupport() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) return;
    try {
      final r = await HostHealth.get(
          Uri.parse('${Brand.panelBase}/api/app/support?tg_id=$tg'),
          timeout: const Duration(seconds: 6));
      if (r == null || r.statusCode != 200) return;
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

  /// Имя пользователя в Telegram, на чей аккаунт оформлена подписка.
  /// Пусто — значит человек его не заводил; тогда показываем ID.
  String subUsername = '';
  bool subLoaded = false;

  /// ЕДИНСТВЕННЫЙ источник правды «можно ли пользоваться полным VPN».
  /// true только при подтверждённой активной подписке (бэкенд /me, личная
  /// ссылка с валидным сроком или кэш последней удачной проверки).
  /// Бесплатный Telegram-режим сюда не входит — у него свой путь.
  bool get hasAccess => subActive;

  /// Открыты ли ВОЗМОЖНОСТИ приложения: маршрутизация, блокировка рекламы,
  /// раздельное туннелирование, настройки пинга и сети.
  ///
  /// Это НЕ то же самое, что [hasAccess]. hasAccess отвечает на вопрос «пустить
  /// ли к НАШИМ платным серверам» — за них платят, и они закрыты. А настройки
  /// туннеля к нашим серверам отношения не имеют: они работают на том сервере,
  /// которым человек пользуется. Если он пришёл со своей подпиской другого
  /// сервиса, запирать от него тумблеры бессмысленно и выглядит как поломка:
  /// подписка добавлена, серверы работают, а половина приложения под замком.
  bool get featuresUnlocked => hasAccess || hasForeignServers;

  /// Подтягивает статус подписки с бэкенда по сохранённому Telegram-ID.
  Future<void> refreshSubStatus() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) {
      subLoaded = true;
      notifyListeners();
      return;
    }
    // Показываем РЕАЛЬНЫЙ статус с бэкенда для всех, включая владельца. Запрос
    // делаем с парой повторов (в момент подключения VPN он мог не дойти —
    // раньше из-за этого дата обнулялась в «—»).
    ({bool active, DateTime? until, String username})? st;
    // Две попытки, а не три, и пауза короче: раньше при недоступном бэкенде
    // экран ждал до 40 секунд, показывая спиннер вместо уже известной даты.
    for (var i = 0; i < 2 && st == null; i++) {
      st = await _api.subStatus(tg);
      if (st == null) await Future.delayed(const Duration(milliseconds: 600));
    }
    if (st != null) {
      subActive = st.active;
      subUntil = st.until;
      if (st.username.isNotEmpty) {
        subUsername = st.username;
        _storage.setStr('sub_username', st.username);
      }
      // Кэшируем — чтобы дата показывалась мгновенно и не пропадала при сбое.
      _storage.setBool('sub_active_cache', st.active);
      _storage.setStr('sub_until_cache', st.until?.toIso8601String() ?? '');
      // Подписка закончилась → снимаем ранее выданный доступ (иначе флаг
      // access_granted оставался «вечным» и возвращал VPN после перезапуска).
      _storage.setBool('access_granted', st.active);
      if (!st.active) await _enforceExpired();
    }
    // Если бэкенд не ответил — оставляем последнее известное значение (не «—»).
    // ВАЖНО: админ-ID больше НЕ даёт принудительный доступ — он публично виден
    // (скриншоты, бот), и любой мог ввести его и получить VPN навсегда.
    // У владельца есть настоящая подписка — она проходит обычную проверку /me.
    subLoaded = true;
    if (subActive) await _onSubActivated();
    notifyListeners();
  }

  /// Подписка закончилась, а полный туннель ещё поднят — гасим его и ведём на
  /// продление. Бесплатный Telegram-режим не трогаем (он и так без подписки).
  Future<void> _enforceExpired() async {
    if (!isConnected || telegramOnly) return;
    _log('Подписка закончилась — отключаю VPN', LogKind.notice);
    await _safeDisconnect();
    _notify('Подписка закончилась. Продли её, чтобы пользоваться VPN.');
    notifyListeners();
  }

  /// Периодическая проверка подписки (раз в 30 мин): чтобы окончание срока
  /// применялось и во время долгой сессии, а не только при перезапуске.
  Timer? _subGuardTimer;
  void _startSubGuard() {
    _subGuardTimer?.cancel();
    _subGuardTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      // Срок уже известен и прошёл — не ждём ответа бэкенда.
      if (subUntil != null && subUntil!.isBefore(DateTime.now()) && subActive) {
        subActive = false;
        _storage.setBool('sub_active_cache', false);
        _storage.setBool('access_granted', false);
        await _enforceExpired();
        notifyListeners();
        return;
      }
      await refreshSubStatus();
    });
  }

  /// Без привязки Telegram-ID подтягивает срок окончания из сохранённой личной
  /// ссылки подписки (заголовок `subscription-userinfo: expire=`). Так дата
  /// показывается и самовосстанавливается после перезапуска, даже если импорт
  /// делали без TG. Если TG привязан — источник правды /me, метод не нужен.
  Future<void> _refreshExpiryFromPersonalLink() async {
    if ((_storage.tgId ?? '').isNotEmpty) return; // есть TG → /me главнее
    final link = _storage.getStr('personal_sub_url', def: '');
    if (link.isEmpty) return;
    final exp = await _api.subExpiryFromUrl(link);
    if (exp == null) return;
    subUntil = exp;
    final expired = exp.isBefore(DateTime.now());
    subActive = !expired;
    subLoaded = true;
    _storage.setBool('sub_active_cache', !expired);
    _storage.setStr('sub_until_cache', exp.toIso8601String());
    _storage.setBool('access_granted', !expired);
    notifyListeners();
  }

  /// Загружает кэш статуса подписки (для мгновенного показа даты на старте).
  void _loadSubCache() {
    // Кэш применим, если привязан TG ИЛИ доступ выдан импортом по ссылке —
    // тогда дата окончания из заголовка подписки тоже сохранена в кэше.
    final hasTg = (_storage.tgId ?? '').isNotEmpty;
    final granted = _storage.getBool('access_granted', def: false);
    if (!hasTg && !granted) return;
    subUsername = _storage.getStr('sub_username');
    subActive = _storage.getBool('sub_active_cache', def: false);
    final iso = _storage.getStr('sub_until_cache', def: '');
    if (iso.isNotEmpty) subUntil = DateTime.tryParse(iso);
    // Дата важнее флага: срок в прошлом = доступа нет, даже если кэш «активна».
    if (subUntil != null && subUntil!.isBefore(DateTime.now())) {
      subActive = false;
      _storage.setBool('sub_active_cache', false);
      _storage.setBool('access_granted', false);
    }
    if (subUntil != null || subActive) subLoaded = true;
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
        _storage.subUrl = _subSource;
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
    final unwrapped = _unwrapSubLink(t);
    final lower =
        unwrapped.toLowerCase(); // схема URL регистронезависима (Https:// тоже)
    final isUrl =
        (lower.startsWith('http://') || lower.startsWith('https://')) &&
            !unwrapped.contains('\n');
    return isUrl ? importFromUrl(unwrapped) : importFromContent(unwrapped);
  }

  /// Достаёт настоящий https-адрес из «клиентских» ссылок-обёрток.
  ///
  /// Люди копируют подписку не голым адресом, а кнопкой «добавить в приложение»
  /// — и получают `happ://add/<base64>`, `v2rayng://install-sub?url=…`,
  /// `clash://install-config?url=…`, `sub://<base64>`. Раньше такая ссылка
  /// уходила в разбор конфигов, там не опознавалась, и человек видел «не удалось
  /// распознать ни одного сервера». Разворачиваем их сами.
  String _unwrapSubLink(String input) {
    final t = input.trim();
    final lower = t.toLowerCase();

    // 1) ?url=<urlencoded> — v2rayng, clash, shadowrocket, nekobox…
    final q = Uri.tryParse(t)?.queryParameters['url'];
    if (q != null && q.startsWith('http')) return Uri.decodeFull(q);

    // 2) схема://[add/]<base64 от адреса> — happ, sub, streisand…
    for (final scheme in const [
      'happ://add/',
      'happ://',
      'sub://',
      'streisand://import/',
    ]) {
      if (!lower.startsWith(scheme)) continue;
      var payload = t.substring(scheme.length);
      final amp = payload.indexOf('&');
      if (amp > 0) payload = payload.substring(0, amp);
      if (payload.startsWith('http')) return payload;
      final decoded = _tryBase64(payload);
      if (decoded != null && decoded.startsWith('http')) return decoded.trim();
    }

    // 3) голый base64 от https-адреса (встречается в QR-кодах).
    if (!lower.startsWith('http') && !t.contains('://') && t.length > 20) {
      final decoded = _tryBase64(t);
      if (decoded != null &&
          decoded.trim().startsWith('http') &&
          !decoded.trim().contains('\n')) {
        return decoded.trim();
      }
    }
    return t;
  }

  String? _tryBase64(String v) {
    try {
      var s = v.replaceAll('-', '+').replaceAll('_', '/').trim();
      s = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
      return utf8.decode(base64.decode(s));
    } catch (_) {
      return null;
    }
  }

  /// Привязка по Telegram-ID из бота: сохраняем ID, тянем персональную подписку
  /// и статус. Успех, если подтянулись серверы ИЛИ подписка активна.
  /// Последняя попытка входа по ID уперлась в отсутствие подписки.
  ///
  /// Отдельно от lastError: «нет подписки» — не ошибка ввода, а развилка, и
  /// экран отвечает на неё предложением оформить, а не красной плашкой.
  bool needsSubscription = false;

  Future<bool> importFromTgId(String id) async {
    needsSubscription = false;
    // ЗАЩИТА: проверяем, что за этим ID реально есть АКТИВНАЯ подписка. Иначе
    // любой случайный набор цифр давал бы полный доступ (панель /vsub отдаёт
    // общие серверы всем). Пускаем только реального подписчика или админа.
    if (!await _idHasActiveSub(id)) {
      _log('Импорт по ID $id отклонён: /me не подтвердил активную подписку',
          LogKind.error);
      // Разные причины — разные слова. Раньше при недоступном сервере человек
      // читал «подписки нет» и шёл проверять ID, хотя ID был верный.
      // Сервер ответил и подписки нет — это развилка, а не ошибка: экран
      // покажет шторку с предложением оформить. Плашку в этом случае не
      // показываем, иначе человек увидит два сообщения об одном и том же.
      needsSubscription = _idCheckReachedServer;
      lastError = _idCheckReachedServer
          ? L.t('id_no_sub')
          : L.t('id_no_server');
      if (!needsSubscription) _notify(lastError!, error: true);
      notifyListeners();
      return false;
    }
    setTgId(id);
    bool ok = false;
    try {
      ok = await importFromUrl(Brand.subForId(id), validated: true);
    } catch (_) {
      ok = false;
    }
    await refreshSubStatus();
    await loadStreak();
    return ok || subActive || hasServers;
  }

  /// true, если у Telegram-ID есть активная подписка (по /me, с парой повторов
  /// на случай сетевого сбоя) ИЛИ это админ. Используется как проверка перед
  /// выдачей доступа по ID — чтобы случайные цифры не открывали VPN.
  /// Ответил ли наш сервер при последней проверке ID. Нужен, чтобы отличить
  /// «подписки нет» от «мы не смогли спросить»: причины разные, и человеку
  /// надо говорить разное.
  bool _idCheckReachedServer = false;

  Future<bool> _idHasActiveSub(String id) async {
    // Без исключений для админ-ID: он публично виден, а у владельца есть
    // настоящая подписка — проверяется как у всех через /me.
    _idCheckReachedServer = false;
    for (var i = 0; i < 2; i++) {
      final st = await _api.subStatus(id);
      if (st != null) {
        _idCheckReachedServer = true;
        return st.active;
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }
    return false; // бэкенд не подтвердил подписку — доступ не выдаём
  }

  /// Проверяет, что сервер/подписка принадлежит НАШЕМУ VPN (хост оканчивается
  /// на Brand.rootDomain). Так пользователь не сможет добавить в приложение
  /// подписку стороннего сервиса.
  bool _isOurHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();
    if (h == Brand.rootDomain || h.endsWith('.${Brand.rootDomain}')) {
      return true;
    }
    // наши серверы часто заданы по IP, а не по домену
    return knownServerIps.contains(h);
  }

  /// true, если ВСЕ серверы из подписки — наши.
  bool _allOurs(List<VpnServer> list) =>
      list.isNotEmpty && list.every((s) => _isOurHost(s.address));

  /// Импорт по subscription-ссылке (грузим с бэкенда, парсим, сохраняем).
  /// [validated] = true, если подписка уже проверена вызывающим (importFromTgId).
  Future<bool> importFromUrl(String url, {bool validated = false}) async {
    _setBusy(true);
    try {
      final u = Uri.tryParse(url.trim());
      if (!_isOurHost(u?.host)) {
        // ЧУЖАЯ подписка. Приложение работает как обычный VPN-клиент: качаем
        // её серверы и добавляем к списку. Доступ к НАШИМ платным серверам она
        // не даёт — он по-прежнему только по подписке (см. connect()).
        // await, а не голый return: без него ошибка импорта чужой подписки
        // прошла бы мимо catch этого же метода, и вместо понятного сообщения
        // человек получил бы необработанный сбой.
        return await _importForeignSub(url.trim());
      }
      // ЗАЩИТА: доступ выдаёт только ПЕРСОНАЛЬНАЯ ссылка с реальной активной
      // подпиской. Панель /vsub отдаёт общие серверы всем, поэтому без проверки
      // любой /vsub/12345, /sub/{случайный-uuid} или общий /vsub открывали VPN.
      DateTime? linkExpiry; // срок из личной ссылки (для даты «Действует до»)
      var grantsAccess = validated;
      if (!validated) {
        // Хвостовой слэш встречается сплошь и рядом (сканеры QR, копипаст из
        // браузера). Без его срезания ссылка не опознавалась как персональная
        // и импорт отвечал «это общая ссылка без подписки».
        final path = (u?.path ?? '').replaceAll(RegExp(r'/+$'), '');
        final mTg = RegExp(r'/vsub/(\d{4,15})$').firstMatch(path);
        final mUuid =
            RegExp(r'/sub/([0-9a-fA-F-]{16,64})$', caseSensitive: false)
                .firstMatch(path);
        if (mTg != null) {
          // Ссылка бота с Telegram-ID → подписка должна быть активна по /me.
          if (!await _idHasActiveSub(mTg.group(1)!)) {
            lastError = 'Подписка по этой ссылке не найдена или истекла. '
                'Возьми свежую ссылку в нашем боте.';
            _notify(lastError!, error: true);
            return false;
          }
          grantsAccess = true;
        } else if (mUuid != null) {
          // Личная ссылка /sub/{uuid}. Основная проверка — срок из заголовка
          // подписки. Если заголовок не дошёл (медленная сеть/таймаут), НЕ
          // отказываем сразу: проверяем сами конфиги — у несуществующего uuid
          // ответ пустой, поэтому непустой список сам по себе подтверждает
          // реальную учётку. Раньше единственный неудачный запрос давал
          // «подписка не найдена» при живой подписке.
          linkExpiry = await _api.subExpiryFromUrl(url.trim());
          if (linkExpiry != null && linkExpiry.isBefore(DateTime.now())) {
            lastError = 'Подписка закончилась. Продли её в нашем боте.';
            _notify(lastError!, error: true);
            return false;
          }
          if (linkExpiry == null) {
            var personalOk = false;
            try {
              final raw = await _api.fetchSubscription(url.trim());
              personalOk = SubscriptionParser.parseContent(raw)
                  .where((s) => s.xraySupported)
                  .isNotEmpty;
            } catch (_) {
              personalOk = false;
            }
            if (!personalOk) {
              lastError = 'Не удалось проверить подписку. Проверь интернет и '
                  'попробуй ещё раз — или возьми свежую ссылку в боте.';
              _notify(lastError!, error: true);
              return false;
            }
          }
          grantsAccess = true;
          // Привязываем аккаунт владельца ссылки: без Telegram-ID не работали
          // «огонёк серии», ник и ID в профиле — приложение не знало, чей доступ.
          if ((_storage.tgId ?? '').isEmpty) {
            final owner = await _api.ownerOfSubUuid(mUuid.group(1)!);
            if (owner != null && owner.isNotEmpty) setTgId(owner);
          }
        } else if (!hasAccess) {
          // Общая ссылка (например, голый /vsub) доступ не даёт — только
          // обновляет серверы тем, у кого подписка уже активна.
          _log(
              'Импорт отклонён: ссылка не персональная ($path)', LogKind.error);
          lastError = 'Это общая ссылка без подписки. Возьми персональную '
              'ссылку или ID в нашем боте.';
          _notify(lastError!, error: true);
          return false;
        }
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
        lastError =
            'Не удалось получить серверы. Проверь интернет и попробуй ещё '
            'раз (или возьми свежую ссылку в боте).';
        return false;
      }
      servers = parsed;
      _assignDisplayNames();
      _appendCustomServers(); // не теряем свои JSON-серверы после обновления подписки
      _appendForeignServers();
      // Для «Обновить» запоминаем ЛИЧНУЮ ссылку: общий список зависит от
      // панели, а личный собирается и напрямую с живых узлов.
      _storage.subUrl = _subSource;
      await _storage.saveConfigsBlob(servers.map((s) => s.raw).join('\n'));
      if (grantsAccess) {
        // Личную ссылку сохраняем отдельно (для «Обновить» используется общий
        // panelSub, у которого срока нет) — чтобы обновлять дату и статус из
        // неё после перезапуска.
        _storage.setStr('personal_sub_url', url.trim());
        _grantAccessFromImport(until: linkExpiry);
        // Если срок ещё не известен (путь через ID) — дотянем в фоне.
        if (linkExpiry == null) _refreshExpiryFromPersonalLink();
      }
      _log(
          'Импортирована подписка: ${servers.length} серверов '
          '(доступ: ${grantsAccess ? "выдан" : "уже был"})',
          LogKind.info);
      // Профиль и серия появляются сразу после импорта (ID уже привязан выше).
      if (grantsAccess && (_storage.tgId ?? '').isNotEmpty) {
        loadStreak();
        _reportStreak();
      }
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
  void _grantAccessFromImport({DateTime? until}) {
    if (telegramOnly) {
      telegramOnly = false;
      _storage.setBool('telegram_only', false);
    }
    // Если срок известен и уже в прошлом — подписка просрочена: НЕ выдаём полный
    // доступ (иначе импорт старой ссылки открывал бы VPN). Дату всё равно
    // сохраняем, чтобы показать «истекла» и вести на продление.
    final expired = until != null && until.isBefore(DateTime.now());
    subActive = !expired;
    subLoaded = true;
    if (until != null) {
      subUntil = until;
      _storage.setBool('sub_active_cache', !expired);
      _storage.setStr('sub_until_cache', until.toIso8601String());
    }
    _storage.setBool('access_granted', !expired);
  }

  /// Доливает в [into] все включённые серверы из панели (/vsub), которых там
  /// ещё нет (по id). Панель — самый надёжный источник полного списка стран.
  Future<void> _mergePanelServers(List<VpnServer> into) async {
    try {
      final praw = await _api.fetchSubscription(_subSource);
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


  /// Откуда перекачивать список серверов.
  ///
  /// Привязан Telegram-ID → ЛИЧНАЯ ссылка: она работает и когда панель лежит
  /// (субсервер соберёт список с живых узлов) и отдаёт срок подписки в
  /// заголовках. Общий /vsub оставляем только тем, у кого ID ещё нет: он
  /// зависит от панели и анониму ничего не отдаёт.
  String get _subSource {
    final tg = _storage.tgId;
    return (tg != null && tg.isNotEmpty) ? Brand.subForId(tg) : Brand.panelSub;
  }

  /// Обновляет ВСЕ подписки, которые есть у человека: нашу (если привязана
  /// ссылка) и все добавленные чужие.
  ///
  /// Раньше кнопка умела только нашу и, не найдя сохранённой ссылки, отвечала
  /// «подписка не привязана — импортируй заново». У человека со своей
  /// подпиской другого сервиса это выглядело как неработающая кнопка: подписка
  /// есть, серверы есть, а обновить их нечем.
  Future<bool> refreshSubscription() async {
    final url = _storage.subUrl;
    final hasOurs = url != null && url.isNotEmpty;
    if (!hasOurs && foreignSubUrls.isEmpty) {
      _notify(L.t('refresh_nothing'), error: true);
      return false;
    }

    var ok = false;
    // ВАЖНО: при обновлении подписку заново НЕ проверяем (`validated`).
    // Кнопка «Обновить» перекачивает список серверов у человека, чей доступ уже
    // подтверждён. Раньше она гоняла ссылку через полную проверку — один
    // неответивший запрос к панели (а она периодически лежит) превращал ответ в
    // «подписка не найдена», и кнопка выглядела полностью нерабочей.
    if (hasOurs) ok = await importFromUrl(url, validated: hasAccess);
    var foreignServers = 0;
    if (foreignSubUrls.isNotEmpty) {
      foreignServers = await refreshForeignSubs();
      if (foreignServers > 0) ok = true;
    }

    if (ok) {
      _notify(L.t('refresh_ok', {'n': servers.length}), success: true);
    } else {
      // Сначала — настоящая причина от сервиса, если она известна. Общая
      // формулировка остаётся только там, где сказать нечего.
      var why = _foreignFailReason ??
          (isConnected ? L.t('refresh_fail_vpn') : L.t('refresh_fail'));
      // Поднятый туннель — самая частая причина, по которой запрос не доходит
      // до чужой панели. Про неё стоит напомнить прямо здесь.
      if (isConnected && _foreignFailReason != null) {
        why = '$why\n${L.t('fsub_vpn_on')}';
      }
      _notify(why, error: true);
    }
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
        // ЧУЖИЕ конфиги (vless:// от другого сервиса) — принимаем: приложение
        // работает как обычный VPN-клиент. Они помечаются как чужие, поэтому
        // наши платные серверы ими не открываются.
        final all = {..._foreignRaws, ...parsed.map((e) => e.raw)}.toList();
        _foreignRaws = all;
        _storage.setStr('foreign_raws', all.join('\n'));
        servers = servers.where((s) => !s.foreign).toList();
        _appendForeignServers();
        _log('Добавлены свои конфиги: ${parsed.length}', LogKind.info);
        lastError = null;
        return true;
      }
      // ЗАЩИТА: сырой текст НАШИХ конфигов сам по себе доступ НЕ выдаёт (они
      // гуляют публично — панель отдаёт их всем). Принимаем только у тех, чья
      // подписка уже подтверждена; остальных ведём в бот.
      if (!hasAccess) {
        await refreshSubStatus();
        if (!hasAccess) {
          lastError = 'Готовые конфиги Various VPN доступны только с активной '
              'подпиской. Вставь персональную ссылку или ID из нашего бота.';
          _notify(lastError!, error: true);
          return false;
        }
      }
      servers = parsed;
      _assignDisplayNames();
      _appendCustomServers();
      _appendForeignServers();
      await _storage.saveConfigsBlob(content);
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
              : (item is Map
                  ? (item['link'] ?? item['url'] ?? '').toString()
                  : '');
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
    _appendForeignServers();
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
        if (g['serviceName'] != null) {
          q['serviceName'] = g['serviceName'].toString();
        }
      } else if (net == 'ws') {
        final w = (ss['wsSettings'] as Map?) ?? const {};
        if (w['path'] != null) q['path'] = w['path'].toString();
        final h = (w['headers'] as Map?)?['Host'];
        if (h != null) q['host'] = h.toString();
      }
    }

    String qstr(Map<String, String> q) => q.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
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

  // ---- ЧУЖИЕ подписки (приложение как обычный VPN-клиент) ----
  //
  // Ссылки не с нашего домена: человек может пользоваться приложением со своей
  // подпиской от другого сервиса. Такие серверы подключаются БЕЗ нашей оплаты,
  // но и наши платные серверы ими не открываются — доступ к ним по-прежнему
  // даёт только подписка (см. connect()).
  List<String> foreignSubUrls = const [];

  /// Срок окончания КАЖДОЙ чужой подписки, взятый из её собственного ответа
  /// (стандартный заголовок `subscription-userinfo`).
  ///
  /// Отдельно от [subUntil] — и это принципиально. subUntil — срок НАШЕЙ
  /// оплаченной подписки, от него зависит доступ к нашим платным серверам.
  /// Раньше срока у чужих подписок не было вовсе, и рядом с добавленной чужой
  /// ссылкой показывалась наша дата — выглядело так, будто приложение считает
  /// её нашей.
  Map<String, DateTime> foreignUntil = const {};

  /// Дата окончания конкретной чужой подписки (null — сервис её не сообщает).
  DateTime? foreignSubUntil(String url) => foreignUntil[url];

  /// Название сервиса и остаток трафика по каждой чужой подписке — то, что она
  /// сообщает о себе в заголовках ответа.
  Map<String, SubInfo> foreignInfo = {};

  SubInfo? foreignSubInfo(String url) => foreignInfo[url];

  /// Сведения о подписке ХРАНИМ, а не только держим в памяти.
  ///
  /// Без этого после перезапуска карточка подписки теряла название, срок и
  /// трафик и превращалась в пустую строку с адресом — выглядело так, будто
  /// приложение забыло подписку. Заголовки перезапрашиваются в фоне, но
  /// показать что-то надо сразу.
  void _saveForeignInfo() {
    _storage.setStr(
      'foreign_info',
      jsonEncode(foreignInfo.map((k, v) => MapEntry(k, {
            't': v.title,
            'u': v.until?.millisecondsSinceEpoch,
            'used': v.used,
            'total': v.total,
          }))),
    );
  }

  void _loadForeignInfo() {
    final raw = _storage.getStr('foreign_info', def: '');
    if (raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map;
      foreignInfo = m.map((k, v) {
        final e = v as Map;
        final ts = e['u'] as int?;
        return MapEntry(
          '$k',
          SubInfo(
            title: '${e['t'] ?? ''}',
            until:
                ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts),
            used: (e['used'] as num?)?.toInt() ?? 0,
            total: (e['total'] as num?)?.toInt() ?? 0,
          ),
        );
      });
    } catch (_) {
      foreignInfo = {};
    }
  }

  /// Спрашивает у чужого сервиса, что он о своей подписке рассказывает: срок,
  /// название, трафик. Молча ничего не делает, если сервис молчит, — это
  /// нормально, обязательным этот заголовок не является.
  Future<void> _loadForeignExpiry(String url) async {
    try {
      final info = await _api.subInfoFromUrl(url);
      if (info == null) return;
      foreignInfo = {...foreignInfo, url: info};
      _saveForeignInfo();
      if (info.until != null) {
        foreignUntil = {...foreignUntil, url: info.until!};
        _saveForeignUntil();
      }
      notifyListeners();
    } catch (_) {
      // сведения — приятное дополнение, из-за них импорт падать не должен
    }
  }

  void _saveForeignUntil() {
    _storage.setStr(
      'foreign_until',
      foreignUntil.entries
          .map((e) => '${e.key}\t${e.value.millisecondsSinceEpoch}')
          .join('\n'),
    );
  }
  List<String> _foreignRaws = const [];

  /// Есть ли импортированные чужие серверы — ими можно подключаться бесплатно.
  ///
  /// Смотрим на САМ список серверов, а не на сохранённые ссылки: серверы
  /// теперь восстанавливаются ещё и из сохранённых тел подписок, и признак,
  /// завязанный только на ссылки, показывал бы «своей подписки нет» при живых
  /// работающих серверах.
  bool get hasForeignServers =>
      _foreignRaws.isNotEmpty || servers.any((s) => s.foreign);

  /// Забыть чужую подписку целиком (ссылку и её серверы).
  Future<void> removeForeignSub(String url) async {
    foreignSubUrls = foreignSubUrls.where((e) => e != url).toList();
    _storage.setStr('foreign_subs', foreignSubUrls.join('\n'));
    foreignUntil = {...foreignUntil}..remove(url);
    _saveForeignUntil();
    foreignInfo = {...foreignInfo}..remove(url);
    _saveForeignInfo();
    _foreignBodies.remove(url);
    unawaited(_saveForeignBodies());
    if (foreignSubUrls.isEmpty) {
      _foreignRaws = const [];
      _storage.setStr('foreign_raws', '');
      servers = servers.where((s) => !s.foreign).toList();
      _assignDisplayNames();
      notifyListeners();
      return;
    }
    await refreshForeignSubs();
  }

  /// Перекачивает все чужие подписки и обновляет их серверы.
  ///
  /// Возвращает число серверов; -1 — ни одну подписку скачать не удалось.
  /// По этому числу экран говорит человеку, что произошло: молчаливая кнопка
  /// выглядит как неработающая.
  Future<int> refreshForeignSubs() async {
    if (foreignSubUrls.isEmpty) return 0;
    _setBusy(true);
    notifyListeners();
    try {
      return await _doRefreshForeignSubs();
    } finally {
      _setBusy(false);
      notifyListeners();
    }
  }

  Future<int> _doRefreshForeignSubs() async {
    // Подписки качаем ПАРАЛЛЕЛЬНО. Раньше шли по очереди, и при двух-трёх
    // подписках с медленной панелью обновление тянулось десятками секунд.
    _foreignFailReason = null;
    final results = await Future.wait(foreignSubUrls.map(_refreshOneForeign));
    // Ни один сервис не ответил — честно сообщаем об этом, а не показываем
    // «обновлено» на основании старых, уже лежащих на диске данных.
    if (!results.contains(true)) return -1;

    final raws = <String>[];
    for (final url in foreignSubUrls) {
      final body = _foreignBodies[url];
      if (body == null) continue;
      raws.addAll(SubscriptionParser.parseDetailed(body).usable.map((s) => s.raw));
    }
    if (raws.isEmpty) return -1;
    unawaited(_saveForeignBodies());
    _foreignRaws = raws;
    _storage.setStr('foreign_raws', raws.join('\n'));
    servers = servers.where((s) => !s.foreign).toList();
    _appendForeignServers();
    notifyListeners();
    return raws.length;
  }

  /// Скачивает ОДНУ чужую подписку и запоминает её тело.
  /// Возвращает true, если сервис ответил и тело обновилось.
  ///
  /// Отличать «скачали заново» от «оставили старое» обязательно: иначе кнопка
  /// рапортует об успехе, даже когда ни один сервис не ответил.
  /// Причина последней неудачи обновления — в человеческом виде.
  ///
  /// Раньше кнопка на любую беду отвечала «сервис не ответил». Код ошибки был
  /// известен всегда, просто не доезжал до экрана, и человек не знал, чинить
  /// ему ссылку, сертификат или отключить VPN.
  String? _foreignFailReason;

  Future<bool> _refreshOneForeign(String url) async {
    unawaited(_loadForeignExpiry(url)); // срок мог измениться после продления
    try {
      // fetchForeignSubscription перебирает User-Agent'ы: часть панелей
      // отдаёт подписку только «знакомым» клиентам. Обычный запрос от них
      // получал пустой ответ, и обновление молча ничего не делало.
      final raw = await _api.fetchForeignSubscription(url,
          isUsable: (body) =>
              SubscriptionParser.parseDetailed(body).usable.isNotEmpty);
      // Свежее тело — свежие конфиги (сервис мог поменять маршрутизацию).
      _foreignBodies = {..._foreignBodies, url: raw};
      return true;
    } on ForeignSubError catch (e) {
      _foreignFailReason = L.t('fsub_${e.code}');
      _log('Подписка не обновилась ($url): $e', LogKind.info);
      return false;
    } catch (e) {
      _foreignFailReason = null;
      _log('Подписка не обновилась ($url): $e', LogKind.info);
      return false;
    }
  }


  /// Импорт подписки СТОРОННЕГО сервиса. Скачиваем, разбираем, добавляем к
  /// списку и запоминаем ссылку, чтобы обновлять её вместе с нашей.
  Future<bool> _importForeignSub(String url) async {
    SubParseResult result;
    try {
      // Та же проверка годности, что и при обновлении: панель может отдать
      // подписку-пустышку любому клиенту, и без неё добавление «удавалось»,
      // а в списке появлялся несуществующий сервер.
      final raw = await _api.fetchForeignSubscription(url,
          isUsable: (body) =>
              SubscriptionParser.parseDetailed(body).usable.isNotEmpty);
      result = SubscriptionParser.parseDetailed(raw);
      // Тело запоминаем целиком: в нём готовые конфиги сервиса со своей
      // маршрутизацией. По одним ссылкам их потом не восстановить.
      if (result.usable.isNotEmpty) {
        _foreignBodies = {..._foreignBodies, url: raw};
        unawaited(_saveForeignBodies());
      }
    } catch (e) {
      // Причину показываем ЧЕЛОВЕКУ, а не прячем за «проверь интернет»: по
      // такому сообщению невозможно понять, что делать дальше.
      _log('Чужая подписка не скачалась: $e', LogKind.error);
      lastError = e is ForeignSubError
          ? L.t('fsub_${e.code}')
          : L.t('fsub_timeout');
      // Самая частая причина, которую человек сам не свяжет: VPN сейчас поднят
      // через наш сервер, и запрос к чужой панели идёт по этому же туннелю.
      // Если туннель нерабочий — падает и загрузка подписки.
      if (isConnected) lastError = '${lastError!}\n\n${L.t('fsub_vpn_on')}';
      _notify(lastError!, error: true);
      return false;
    }
    // Три РАЗНЫЕ причины, за которыми стоят три разных действия человека.
    // Раньше все три сводились к одной фразе «нет серверов, которые мы умеем»,
    // по которой нельзя было понять ни что случилось, ни что делать дальше.
    final parsed = result.usable;
    if (parsed.isEmpty) {
      final skipped = result.unsupportedLabels;
      lastError = switch (0) {
        // Ответ пришёл, но это не подписка — ни ссылок, ни конфига.
        _ when result.format == SubFormat.unknown => L.t('fsub_unreadable'),
        // Формат понятен, узлы есть, но все на чужих для ядра протоколах.
        _ when skipped.isNotEmpty =>
          L.t('fsub_other_proto', {'list': skipped.join(', ')}),
        // Формат понятен, а узлов внутри нет.
        _ => L.t('fsub_no_servers'),
      };
      _notify(lastError!, error: true);
      return false;
    }
    // Добавляем к уже сохранённым (у человека может быть несколько подписок),
    // без дублей по самой ссылке-конфигу.
    final all = {..._foreignRaws, ...parsed.map((e) => e.raw)}.toList();
    _foreignRaws = all;
    _storage.setStr('foreign_raws', all.join('\n'));
    if (!foreignSubUrls.contains(url)) {
      foreignSubUrls = [...foreignSubUrls, url];
      _storage.setStr('foreign_subs', foreignSubUrls.join('\n'));
    }
    servers = servers.where((s) => !s.foreign).toList();
    _appendForeignServers();
    // Срок берём из САМОЙ подписки, а не из нашей. Запрос фоновый: серверы уже
    // готовы, и ждать ради даты человеку незачем.
    unawaited(_loadForeignExpiry(url));
    _log(
        'Добавлена чужая подписка (${result.format.label}): '
        '${parsed.length} серверов',
        LogKind.info);
    // Часть узлов могла отсеяться по протоколу. Молчать об этом нельзя: человек
    // видит в подписке 12 серверов, в приложении 8 и решает, что мы потеряли
    // остальные. Говорим прямо, сколько и почему.
    final skipped = result.servers.length - parsed.length;
    if (skipped > 0) {
      _notify(L.t('fsub_partial', {
        'ok': parsed.length,
        'skipped': skipped,
        'list': result.unsupportedLabels.join(', '),
      }));
    }
    lastError = null;
    notifyListeners();
    return true;
  }

  /// Добавляет сохранённые чужие серверы к списку (после синка с панелью).
  void _appendForeignServers() {
    final existing = servers.map((e) => e.id).toSet();

    // Сначала — серверы из СОХРАНЁННЫХ ТЕЛ подписок. Только там остаются
    // готовые конфиги с чужой маршрутизацией и DNS; по одной ссылке их не
    // восстановить.
    for (final body in _foreignBodies.values) {
      for (final s in SubscriptionParser.parseDetailed(body).usable) {
        if (!existing.add(s.id)) continue;
        s.foreign = true;
        servers = [...servers, s];
      }
    }
    // Затем — всё, что осталось только ссылками (подписки-списки и то, что
    // сохранили прошлые версии приложения).
    for (final raw in _foreignRaws) {
      final s = SubscriptionParser.parseLink(raw);
      if (s != null && existing.add(s.id)) {
        s.foreign = true;
        servers = [...servers, s];
      }
    }
    _assignDisplayNames();
  }

  /// Сырые тела чужих подписок: ссылка → ответ сервиса.
  /// Держим их, чтобы после перезапуска у серверов остались полные конфиги.
  Map<String, String> _foreignBodies = {};

  Future<void> _saveForeignBodies() =>
      _storage.saveNamedBlob('foreign_bodies', jsonEncode(_foreignBodies));

  Future<void> _loadForeignBodies() async {
    try {
      final raw = await _storage.loadNamedBlob('foreign_bodies');
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map;
      _foreignBodies = m.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      _foreignBodies = {};
    }
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

  /// Счётчик РУЧНЫХ выборов сервера.
  ///
  /// Нужен, чтобы отличить «пользователь ткнул в другую страну, пока мы
  /// переключались» от «мы сами ушли на запасной сервер». Без этого запасной
  /// перебор выглядел как новый выбор человека, переподключение звало себя
  /// снова и снова, туннель пересоздавался каждые несколько секунд и не
  /// успевал пропустить ни байта.
  int _userPick = 0;

  void setManualServer(String serverId) {
    _userPick++;
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

  /// Последний сервер, на котором связь реально работала. К нему возвращаемся,
  /// если выбранный вручную оказался мёртвым.
  String? _lastGoodServerId;

  /// Выбранный сервер не отвечает — честно говорим об этом и возвращаемся на
  /// рабочий. Молча уходить на другой сервер нельзя (человек выбирал руками),
  /// но и оставлять его без интернета — тоже.
  DateTime? _lastFallback;

  Future<void> _fallbackFromDead(VpnServer dead) async {
    // Не чаще раза в минуту: иначе при нескольких мёртвых серверах подряд
    // приложение уходит в непрерывный перебор и туннель не живёт дольше
    // пары секунд.
    final now = DateTime.now();
    if (_lastFallback != null &&
        now.difference(_lastFallback!).inSeconds < 60) {
      _log('${dead.countryName} не отвечает', LogKind.info);
      return;
    }
    _lastFallback = now;
    final pick = _userPick;
    final pool = _connectCandidates(freeMode: telegramOnly)
        .where((s) => s.id != dead.id && !s.unreachable)
        .toList();
    // Сначала пробуем тот, что работал в прошлый раз.
    final preferred = <VpnServer>[
      ...pool.where((s) => s.id == _lastGoodServerId),
      ...pool.where((s) => s.id != _lastGoodServerId),
    ];
    for (final srv in preferred.take(3)) {
      // Человек ткнул в другой сервер, пока мы перебирали — его выбор важнее.
      if (_userPick != pick) return;
      _log('Пробую ${srv.flag} ${srv.title} вместо ${dead.title}…',
          LogKind.notice);
      try {
        await vpn.connect(srv, rules: rules, net: net, blockedApps: blockedApps);
      } catch (_) {
        srv.unreachable = true;
        continue;
      }
      final ok = telegramOnly ? await _verifyFreeTunnel() : await _tunnelAlive();
      if (!ok) {
        srv.unreachable = true;
        continue;
      }
      srv.unreachable = false;
      _lastGoodServerId = srv.id;
      manualServerId = srv.id;
      _storage.manualServerId = srv.id;
      _log(
          '${dead.countryName} не отвечает — перевёл на '
          '${srv.flag} ${srv.countryName}',
          LogKind.notice);
      notifyListeners();
      return;
    }
    _log('${dead.countryName} не отвечает, рабочих серверов рядом нет',
        LogKind.error);
    notifyListeners();
  }

  /// Жёсткое переподключение к текущему выбранному серверу: полностью гасим
  /// туннель, ДОЖИДАЕМСЯ реального отключения ядра, затем поднимаем заново.
  /// Без ожидания нативный сервис не успевает пересоздать ядро с новым конфигом.
  bool _switching = false;
  Future<void> _reconnectTo() async {
    if (_switching) return;
    _switching = true;
    final pickAtStart = _userPick;
    try {
      // ЗАЩИТА: без активной подписки переподключение НЕ выводит из бесплатного
      // режима. Раньше здесь безусловно стоял telegramOnly=false, и любой тап по
      // серверу (экран «Серверы») поднимал ПОЛНЫЙ туннель без оплаты.
      // featuresUnlocked, а не hasAccess: своя (чужая) подписка — такой же
      // повод переподключиться. С проверкой на одну лишь оплату НАШИХ серверов
      // человек, подключённый по чужой подписке, при смене сервера получал
      // предложение купить нашу — прямо поверх работающего соединения.
      if (featuresUnlocked) {
        telegramOnly = false;
      } else if (!telegramOnly) {
        // Нет доступа и не free-режим — переподключать нечего.
        lastError = 'Нет активной подписки. Оформи её в боте и привяжи ID '
            'или ссылку.';
        _notify(lastError!, error: true);
        notifyListeners();
        return;
      }
      final srv = activeServer;
      if (srv == null) return;
      // Переключение «на лету»: startV2Ray с новым конфигом сам делает
      // stopCore+startCore на том же socks-порту (НЕ полный disconnect —
      // тот на EMUI не переподнимается). Так туннель реально меняет сервер.
      _log('Переключение на ${srv.flag} ${srv.title}…', LogKind.connect);
      try {
        await vpn.connect(srv,
            rules: rules, net: net, blockedApps: blockedApps);
        // ПРОВЕРЯЕМ, что новый сервер реально несёт трафик.
        //
        // Раньше здесь сразу писалось «Сервер: 🇵🇱 Польша» — и всё. Если сервер
        // мёртв (а TCP-пинг до него проходит: отвечает балансировщик, за
        // которым уже ничего нет), приложение бодро рапортовало об успехе,
        // трафик уходил вверх и не возвращался, и человек оставался без
        // интернета, не понимая почему.
        // Даём ядру подняться, прежде чем судить о живости.
        //
        // startV2Ray возвращается, как только конфиг отдан ядру, а не когда
        // туннель заработал: маршруты в этот момент ещё перестраиваются.
        // Проверка сразу после вызова стабильно проваливалась на исправном
        // сервере — он объявлялся мёртвым, и начинался лишний перебор.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        final alive = telegramOnly
            ? await _verifyFreeTunnel()
            : await _tunnelAlive();
        if (alive) {
          srv.unreachable = false;
          _lastGoodServerId = srv.id;
          _log('Сервер: ${srv.flag} ${srv.countryName}', LogKind.notice);
        } else {
          srv.unreachable = true;
          _log('${srv.title}: сервер не отвечает', LogKind.error);
          await _fallbackFromDead(srv);
        }
      } catch (e) {
        srv.unreachable = true;
        _log('Ошибка переключения: $e', LogKind.error);
        _log('Не удалось переключиться на ${srv.countryName}',
            LogKind.error);
      }
    } finally {
      _switching = false;
    }
    // Догоняем ТОЛЬКО новый выбор ЧЕЛОВЕКА. Сравнивать с manualServerId нельзя:
    // его меняет и наш собственный запасной перебор, и тогда переподключение
    // звало себя бесконечно.
    if (_userPick != pickAtStart &&
        (isConnected || _stage == VpnStage.connecting)) {
      _reconnectTo();
    }
  }

  /// Сервер, ВЫБРАННЫЙ авто-режимом. Держится, пока не появится причина уйти.
  ///
  /// Раньше авто-режим не выбирал сервер, а каждый раз пересчитывал «лучшего
  /// прямо сейчас». Из-за этого он менялся на каждом замере — задержка
  /// колеблется сама по себе, — и сравнить «старый против нового» было
  /// невозможно: старым всегда оказывался новый.
  String? _autoServerId;

  /// Сервер, выбранный для общего трафика (с учётом режима).
  VpnServer? get activeServer {
    if (servers.isEmpty) return null;
    if (mode == GlobalMode.manual && manualServerId != null) {
      return servers.firstWhere(
        (s) => s.id == manualServerId,
        orElse: () => _bestServer(),
      );
    }
    // Авто: держимся выбранного, пока он есть в списке.
    final chosen = _autoServerId;
    if (chosen != null) {
      for (final s in servers) {
        if (s.id == chosen) return s;
      }
    }
    // Выбора ещё нет (первый запуск) или сервер пропал из подписки — берём
    // лучшего и запоминаем его как выбранного.
    final best = _bestServer();
    _autoServerId = best.id;
    return best;
  }

  /// Переставить выбор авто-режима (после замеров или падения сервера).
  void _setAutoServer(String id) {
    if (_autoServerId == id) return;
    _autoServerId = id;
    notifyListeners();
  }

  /// «Лучший» сервер = минимальный измеренный пинг среди ПОДДЕРЖИВАЕМЫХ ядром
  /// (Hysteria2/TUIC пропускаем — VPN на них не поднимется). Если поддерживаемых
  /// нет — берём из всех (чтобы хоть что-то показать).
  VpnServer _bestServer() {
    var pool = servers.where((s) => s.xraySupported).toList();
    // Без подписки «лучшим» может быть только сервер своей подписки — иначе
    // на главной показывался бы наш платный сервер, которым не подключиться.
    if (!hasAccess && pool.any((s) => s.foreign)) {
      pool = pool.where((s) => s.foreign).toList();
    }
    // Копия: сортировать сам servers нельзя — порядок в списке задаёт человек.
    final list = List.of(pool.isNotEmpty ? pool : servers);
    _rankBySpeed(list);
    return list.first;
  }

  /// Сортирует серверы «от лучшего к худшему» для автоподключения.
  ///
  /// Главный критерий — ИЗМЕРЕННЫЙ пинг. Раньше первым шёл транспорт, и сервер
  /// на Reality без замера обгонял живой TLS-сервер с 20 мс: ИИ выбирал не
  /// быстрейший, а по сути случайный. Теперь надёжность транспорта — это
  /// добавка в миллисекундах: она решает при близких пингах и не может
  /// перевесить реальную разницу в скорости.
  static void _rankBySpeed(List<VpnServer> list) {
    // httpupgrade/ws на Android нестабильны — им штраф. Сервер без замера
    // ставим за всеми измеренными, но перед признанными нерабочими.
    const unknown = 100000;
    int score(VpnServer s) {
      final base = s.pingMs > 0 ? s.pingMs : unknown;
      return base + s.transportPriority * 60 + (s.unreachable ? 1000000 : 0);
    }

    list.sort((a, b) => score(a).compareTo(score(b)));
  }

  /// Кандидаты для подключения с failover: поддерживаемые серверы по возрастанию
  /// пинга. В ручном режиме выбранный сервер идёт первым.
  /// [freeMode] — подбор для бесплатного режима «только Telegram». Там доступ
  /// не требуется по определению, поэтому фильтр «без подписки только свои
  /// серверы» не применяется: иначе у новичка без подписки список кандидатов
  /// оказывался пустым и бесплатный режим вообще не включался.
  List<VpnServer> _connectCandidates({bool freeMode = false}) {
    var pool = servers.where((s) => s.xraySupported).toList();
    // Без нашей подписки доступны ТОЛЬКО серверы своей (чужой) подписки.
    // Наши платные так и остаются за оплатой — их просто нет в кандидатах.
    if (!hasAccess && !freeMode) {
      pool = pool.where((s) => s.foreign).toList();
    } else if (pool.isEmpty) {
      pool = List.of(servers);
    }
    // Тот же порядок, что и у «лучшего» сервера, — иначе ИИ показывал в списке
    // один сервер, а подключался к другому.
    _rankBySpeed(pool);
    // Первым идёт выбранный сервер: в ручном режиме — выбор человека, в авто —
    // выбор режима. Иначе приложение подключалось бы не к тому серверу, что
    // отмечен в списке.
    final pinned =
        mode == GlobalMode.manual ? manualServerId : _autoServerId;
    if (pinned != null) {
      final i = pool.indexWhere((s) => s.id == pinned);
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
    // ВАЖНО: бесплатный режим снимаем ТОЛЬКО после подтверждения доступа (ниже).
    // Раньше telegramOnly сбрасывался здесь и сохранялся в storage ДО проверки:
    // при отказе free-режим терялся, а замки премиум-настроек (они считались по
    // telegramOnly) открывались у неоплатившего пользователя.
    if (servers.isEmpty) {
      lastError = 'Нет серверов — сначала импортируй подписку';
      _log('Подключение отклонено: нет серверов', LogKind.error);
      notifyListeners();
      return;
    }
    // Полный VPN доступен ТОЛЬКО с активной подпиской (hasAccess). Перед
    // отказом перепроверяем статус (после оплаты и «Обновить» — сразу
    // разблокируется). Бесплатный Telegram-режим идёт через connectTelegramOnly.
    if (!hasAccess) {
      await refreshSubStatus();
      if (!hasAccess) await _refreshExpiryFromPersonalLink();
      // Своя (чужая) подписка — подключаемся по ЕЁ серверам без нашей оплаты:
      // приложение здесь обычный VPN-клиент. Наши платные серверы при этом
      // остаются закрытыми — они отфильтрованы из кандидатов ниже.
      if (!hasAccess && hasForeignServers) {
        _log('Подключение по своей подписке (наши серверы закрыты)',
            LogKind.info);
      } else if (!hasAccess) {
        lastError = subUntil != null
            ? 'Подписка закончилась. Продли её, чтобы подключиться.'
            : 'Нет активной подписки. Оформи её в боте и привяжи ID или ссылку.';
        _log('Подключение отклонено: нет активной подписки', LogKind.error);
        _notify(lastError!, error: true);
        notifyListeners();
        return;
      }
    }
    // Доступ подтверждён — только теперь выходим из бесплатного режима.
    telegramOnly = false;
    _storage.setBool('telegram_only', false);
    final ok = await vpn.requestPermission();
    if (!ok) {
      lastError = 'Нет разрешения на VPN';
      _log('Нет разрешения на VPN', LogKind.error);
      notifyListeners();
      return;
    }
    // Пинги ещё не измерены (первый заход) → быстрый TCP-замер, иначе список
    // кандидатов отсортирован «вслепую» и первым может оказаться недоступный
    // сервер: пользователь ждёт впустую и решает, что VPN не работает.
    // Стадию переключаем СРАЗУ — кнопка уходит в «подключение» без задержки,
    // а замер идёт уже под анимацией (не более 3 с, чтобы не тормозить старт).
    if (servers.every((s) => s.pingMs <= 0)) {
      _stage = VpnStage.connecting;
      notifyListeners();
      await _pingAllSilent(background: true, forceTcp: true)
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    final candidates = _connectCandidates();
    if (candidates.isEmpty) {
      lastError = 'Нет совместимых серверов (нужен VLESS/VMess/Trojan/SS)';
      _log(lastError!, LogKind.error);
      _notify(lastError!, error: true);
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
        if (round >= 2) {
          _log('Повтор с обходом DPI (фрагментация)…', LogKind.notice);
        }
        for (final srv in candidates) {
          _log(
              'Подключение к ${srv.flag} ${srv.title} '
              '(${srv.protocol.label})…',
              LogKind.connect);
          bool alive;
          try {
            alive = await _tryConnect(srv);
          } catch (e) {
            _log('${srv.title}: $e', LogKind.error);
            await _safeDisconnect();
            continue;
          }
          // ПОВТОР НА ТОМ ЖЕ СЕРВЕРЕ. Классика холодного старта (EMUI/Honor):
          // самый первый запуск ядра за день срывается, а сразу следующий —
          // проходит. Раньше мы уходили к другому серверу и перебирали весь
          // список по ~16 с, из-за чего «первое подключение не работает».
          // Теперь сначала честно пробуем этот же сервер ещё раз.
          if (!alive && round == 1) {
            _log('${srv.title}: пробую ещё раз…', LogKind.notice);
            await _safeDisconnect();
            await Future.delayed(const Duration(milliseconds: 700));
            try {
              alive = await _tryConnect(srv);
            } catch (_) {
              alive = false;
            }
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
            _notify(
                'Подключено. Нейросети на этом сервере могут не открываться');
            return;
          }
        } catch (_) {}
      }

      _stage = VpnStage.disconnected;
      lastError = 'Не удалось подключиться — проверь интернет и подписку';
      _notify(lastError!, error: true);
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
    srv.unreachable = false;
    _lastGoodServerId = srv.id;
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
  Map<int, int> streakRewards =
      const {}; // веха → бонус-дни (для экрана наград)
  int _lastSessionMinutes =
      0; // длительность прошлой сессии (для заработка заморозок)

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
          .timeout(const Duration(seconds: 6));
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

  /// Ник из Telegram для профиля.
  ///
  /// Раньше приходил только из админ-панели. Она периодически недоступна, и
  /// профиль тогда показывал голый ID. Тот же ник отдаёт статус подписки —
  /// им и подстраховываемся.
  String _profileUsername = '';
  String get profileUsername =>
      _profileUsername.isNotEmpty ? _profileUsername : subUsername;

  /// Тянет профиль (ник + стрик) для экрана профиля (без отметки дня).
  Future<void> loadStreak() async {
    final tg = _storage.tgId;
    if (tg == null || tg.isEmpty) return;
    try {
      final r = await HostHealth.get(
          Uri.parse('${Brand.panelBase}/api/app/profile?tg_id=$tg'),
          timeout: const Duration(seconds: 6));
      if (r == null || r.statusCode != 200) return;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      _profileUsername = (d['username'] ?? '').toString();
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
      kProbeUrl,
      'http://www.gstatic.com/generate_204',
      'http://connectivitycheck.gstatic.com/generate_204',
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
        final d =
            await vpn.connectedDelay().timeout(const Duration(seconds: 2));
        if (d > 0) return true;
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


  /// Бесплатный режим (до оплаты): поднимает РЕАЛЬНЫЙ рабочий сервер и пускает
  /// через туннель ТОЛЬКО Telegram. Навигацию не блокируем — подключение
  /// устанавливается, экран-инструкция открывается сразу. Возвращает true, если
  /// подключение стартовало.
  Future<bool> connectTelegramOnly() async {
    // Нужен хотя бы один настоящий сервер — берём из панели (тот же /vsub).
    if (servers.where((s) => s.xraySupported).isEmpty) {
      try {
        // Именно БЕСПЛАТНАЯ подписка (/free), а не общий платный список.
        // Раньше сюда тянулся тот же список, что и оплатившим: бесплатный
        // режим фактически раздавал полный доступ, который достаточно было
        // вытащить из приложения и открыть в стороннем клиенте.
        final raw = await _api.fetchFreeSubscription();
        final parsed = SubscriptionParser.parseContent(raw)
            .where((s) => s.xraySupported)
            .toList();
        if (parsed.isNotEmpty) {
          servers = parsed;
          _assignDisplayNames();
          await _storage.saveConfigsBlob(raw);
        }
      } catch (e) {
        _log('Бесплатная подписка недоступна: $e', LogKind.error);
      }
    }
    final ok = await vpn.requestPermission();
    if (!ok) {
      lastError = 'Нет разрешения на VPN';
      notifyListeners();
      return false;
    }
    // Кандидаты по возрастанию пинга — как в платном режиме. Раньше брался
    // ОДИН «лучший по TCP» сервер и подключался без всякой проверки: если он
    // оказывался мёртвым (а TCP-пинг проходит и до сервера, где наш xray уже
    // не отвечает), приложение бодро писало «включено», а Telegram не грузился
    // и починить это было нечем.
    final candidates = _connectCandidates(freeMode: true);
    if (candidates.isEmpty) {
      lastError = 'Не удалось получить сервер — попробуй позже или возьми '
          'подписку в боте';
      _notify(lastError!, error: true);
      notifyListeners();
      return false;
    }
    telegramOnly = true;
    _storage.setBool('telegram_only', true); // переживает перезапуск приложения
    _connecting = true;
    _stage = VpnStage.connecting;
    notifyListeners();
    try {
      for (final srv in candidates.take(4)) {
        _log('Бесплатный режим (только Telegram) → ${srv.flag} ${srv.title}',
            LogKind.connect);
        await _safeDisconnect();
        try {
          // «Только Telegram» реализовано РОУТИНГОМ Xray (net.telegramOnly=true,
          // см. xray_config): к серверу идёт только трафик Telegram, остальное
          // блокируется. САМО приложение выводим из туннеля — иначе вместе с
          // прочим трафиком умирают наши запросы к API и подписку нельзя
          // добавить, не выключив VPN.
          await vpn.connect(srv,
              rules: rules,
              net: net,
              blockedApps: const ['com.example.various_vpn']);
        } catch (e) {
          _log('${srv.title}: $e', LogKind.error);
          continue;
        }
        if (!await _verifyFreeTunnel()) {
          _log('${srv.title}: туннель не отвечает, пробую следующий',
              LogKind.notice);
          continue;
        }
        manualServerId = srv.id;
        if (_stage != VpnStage.connected) {
          _stage = VpnStage.connected;
          _startSession();
        }
        _notify('🆓 Бесплатный VPN включён — работает только Telegram');
        return true;
      }
      await _safeDisconnect();
      _stage = VpnStage.disconnected;
      lastError = 'Серверы сейчас недоступны. Попробуй ещё раз через минуту.';
      _notify(lastError!, error: true);
      return false;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Проверка бесплатного туннеля.
  ///
  /// Обычная проба из приложения тут НЕ работает: в бесплатном режиме наш
  /// пакет намеренно выведен из туннеля, поэтому его запросы уходят напрямую и
  /// возвращают 204 даже при мёртвом сервере. Поэтому спрашиваем САМО ядро:
  /// `connectedDelay()` меряет задержку своим соединением, то есть через
  /// туннель. Адреса проверки специально пропущены через прокси в роутинге
  /// (см. _probeDomains в xray_config), иначе проба ушла бы в blackhole.
  Future<bool> _verifyFreeTunnel() async {
    // Ждём, пока система применит VPN-маршрут.
    await Future.delayed(const Duration(milliseconds: 1500));
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final d = await vpn.connectedDelay();
        if (d > 0) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 900));
    }
    return false;
  }

  Future<void> disconnect() async {
    _log('Отключено', LogKind.disconnect);
    _storage.setBool('was_connected', false); // осознанное отключение
    await vpn.disconnect();
  }

  // ---- пинг ----

  static const _kPingType = 'ping_type'; // 'proxy' | 'tcp'
  static const _kPingUrl = 'ping_test_url';
  static const _kPingEvery = 'ping_every_s'; // 0 = не мерить автоматически

  /// Метод замера: 'tcp' (быстрый) или 'proxy' (точный, рукопожатие TLS).
  ///
  /// Пробовали добавлять ICMP и замер HTTP-запросом. На практике оба чаще
  /// показывали прочерк, чем число: ICMP режут на половине серверов, а запрос
  /// через ядро до неподключённого сервера поднимается не всегда. Оставили два
  /// метода, которые работают всегда. Если в настройках сохранился убранный
  /// метод — молча возвращаем быстрый, иначе замер вообще не запустится.
  String get pingType {
    final v = _storage.getStr(_kPingType, def: 'tcp');
    return (v == 'tcp' || v == 'proxy') ? v : 'tcp';
  }
  set pingType(String v) {
    if (v == _storage.getStr(_kPingType, def: 'tcp')) return;
    _storage.setStr(_kPingType, v);
    // Старые значения СБРАСЫВАЕМ сразу же. Иначе, пока идёт перезамер, часть
    // списка показывает числа прошлого метода — и кажется, что настройка
    // подействовала не на все конфиги или вообще слетела.
    for (final s in servers) {
      s.pingMs = -1;
      s.pingVia = '';
    }
    notifyListeners();
    pingAll();
  }

  /// Как часто перемерять пинг всего списка, секунды. 0 — не мерить.
  ///
  /// Минимум 30 секунд: полный проход сам занимает несколько секунд, и более
  /// частый запуск означает, что приложение занято почти только замером.
  int get pingEveryS {
    final v = _storage.getInt(_kPingEvery, def: 60);
    if (v <= 0) return 0;
    return v < 30 ? 30 : v;
  }
  set pingEveryS(int v) {
    _storage.setInt(_kPingEvery, v);
    _startAiAutoPing(); // применяем новый интервал сразу
    notifyListeners();
  }

  String get pingTestUrl =>
      _storage.getStr(_kPingUrl, def: kProbeUrl);
  set pingTestUrl(String v) {
    _storage.setStr(_kPingUrl, v.trim());
    notifyListeners();
  }

  bool pinging = false; // идёт ручной замер пинга (для спиннеров у конфигов)

  /// Серверы, у которых прямо сейчас идёт одиночный замер (для спиннера в
  /// строке конфига). Общий флаг [pinging] тут не годится: он крутил бы
  /// спиннеры сразу у всех, хотя мерим один.
  final Set<String> pingingIds = {};

  /// Замер пинга ОДНОГО сервера — по кнопке рядом с ним.
  ///
  /// Общий замер на длинном списке идёт секунды, а человеку часто нужен один
  /// конкретный сервер: проверить, ожил ли он.
  Future<void> pingOne(VpnServer s) async {
    if (!pingingIds.add(s.id)) return; // уже мерим — второй раз не запускаем
    notifyListeners();
    try {
      await _pingServer(s);
    } finally {
      pingingIds.remove(s.id);
      notifyListeners();
    }
  }

  Future<void> pingAll() async {
    pinging = true;
    _setBusy(true);
    notifyListeners();
    try {
      await _pingAllSilent();
    } finally {
      pinging = false;
      _setBusy(false);
      notifyListeners();
    }
  }

  /// Сервер, до которого по TCP не достучаться в принципе: Hysteria работает
  /// поверх UDP/QUIC. Пинговать такой можно только силами ядра.
  static bool _udpOnly(VpnServer s) =>
      s.protocol == VpnProtocol.hysteria ||
      s.protocol == VpnProtocol.hysteria2;


  /// Замер ОДНОГО сервера выбранным методом.
  ///
  /// Вынесен отдельно, чтобы кнопка рядом с конфигом и общий замер списка
  /// работали ровно одинаково: раньше повторение этой логики в двух местах
  /// уже приводило к тому, что настройка метода применялась не везде.
  /// Возвращает true, если замер дал число. Проход по списку опирается на это,
  /// чтобы понимать, кого стоит перемерить.
  Future<bool> _pingServer(VpnServer s,
      {bool background = false,
      bool forceTcp = false,
      bool lastChance = false}) async {
    final viaProxy = !forceTcp && pingType == 'proxy';
    final tunnelUp = isConnected;
    var via = (viaProxy || _udpOnly(s)) ? 'proxy' : 'tcp';
    int v;

    // «Точный» замер ВСЕГДА идёт через ядро — и с поднятым туннелем, и без.
    //
    // Это принципиально: ядро поднимает соединение по конфигу сервера и делает
    // настоящий запрос, поэтому число одинаково по смыслу в обоих состояниях.
    // Раньше при выключенном VPN мерили рукопожатием TLS (быстро, ~50 мс), а
    // при включённом — через ядро (полный запрос, ~700 мс). Одна и та же
    // настройка давала числа из разных шкал, и казалось, что с туннелем всё
    // резко «замедлилось».
    //
    // При поднятом туннеле у ядра есть ещё одно преимущество: свой сокет оно
    // помечает как исключённый из VPN (VpnService.protect), поэтому меряет
    // сервер, а не путь через туннель. Обычный сокет так не умеет — вот почему
    // быстрый метод при включённом VPN подменяется точным.
    if (viaProxy || tunnelUp || _udpOnly(s)) {
      via = 'proxy';
      // 4 секунды вместо 8: живой сервер отвечает меньше чем за секунду, а
      // мёртвый всё равно не ответит — лишнее ожидание только растягивает
      // проход по списку.
      v = await vpn
          .ping(s, url: pingTestUrl)
          .timeout(const Duration(seconds: 7), onTimeout: () => -1);
    } else {
      // Быстрый метод: рукопожатие TCP. Имеет смысл только без туннеля —
      // иначе соединение ушло бы через VPN и померяло не то.
      v = await tcpPing(s.address, s.port);
    }

    // Неудача при поднятом туннеле почти наверняка означает «замер не прошёл»,
    // а не «сервер мёртв». Оставляем прошлое значение: иначе весь список разом
    // превращался в прочерки.
    if (v <= 0 && tunnelUp && s.pingMs > 0 && !lastChance) return false;
    // Свежий результат применяем всегда, кроме одного случая: первая попытка
    // фонового прохода, сорвавшаяся у сервера с прошлым значением. Ей даётся
    // повтор (lastChance), и только после него сервер признаётся недоступным —
    // иначе список мигал бы прочерками от каждой случайной осечки.
    if (v > 0 || !background || lastChance) {
      s.pingMs = v;
      s.pingVia = via;
    }
    return v > 0;
  }

  /// Идёт полный замер списка (для индикатора на экране).
  bool pingSweepRunning = false;

  /// Сколько серверов уже померяно в текущем проходе и сколько всего.
  int pingSweepDone = 0;
  int pingSweepTotal = 0;

  /// Был ли ХОТЯ БЫ ОДИН полный проход после запуска.
  ///
  /// Автовыбор включается только после него. Иначе «лучшим» становится первый
  /// попавшийся сервер: у остальных замера ещё нет, сравнивать не с чем.
  bool pingSweepEverCompleted = false;

  /// Полный замер ВСЕХ серверов.
  ///
  /// Идёт параллельно небольшими группами и обновляет экран после каждого
  /// готового сервера — числа появляются по мере измерения, а не все разом в
  /// конце. Группами, а не все сразу: десяток одновременных рукопожатий душит
  /// сеть телефона, часть замеров отваливалась по таймауту и в списке
  /// оставались прочерки.
  /// Человек прямо сейчас тащит карточку сервера.
  ///
  /// Пока это так, замер НЕ дёргает перерисовку списка: каждое обновление
  /// пересобирает карточки и срывает захват. Из-за этого во время прохода по
  /// серверам конфиги переставить было невозможно.
  bool listDragging = false;

  void setListDragging(bool v) {
    if (listDragging == v) return;
    listDragging = v;
    if (!v) notifyListeners(); // показываем всё, что накопилось за время таскания
  }

  DateTime _lastSweepNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Уведомление во время прохода: не чаще четырёх раз в секунду.
  /// Раньше перерисовка шла на каждый сервер — список мигал и не давал себя
  /// перетаскивать.
  void _sweepNotify({bool force = false}) {
    if (listDragging) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSweepNotify).inMilliseconds < 250) return;
    _lastSweepNotify = now;
    notifyListeners();
  }

  Future<void> _pingAllSilent(
      {bool background = false, bool forceTcp = false}) async {
    final list = List.of(servers);
    if (list.isEmpty) return;

    pingSweepRunning = true;
    pingSweepDone = 0;
    pingSweepTotal = list.length;
    notifyListeners();

    final heavy = !forceTcp && pingType == 'proxy';
    // При поднятом туннеле меряем ОСТОРОЖНО, по два за раз.
    //
    // Каждый замер через ядро — это не «ещё один запрос», а отдельный полный
    // экземпляр Xray. На телефоне это видно в логах: шесть параллельных замеров
    // по два десятка серверов поднимали под полсотни экземпляров за полминуты,
    // и живой туннель оставался без процессора. Со стороны выглядело так:
    // «Подключено», а трафик стоит.
    //
    // Без туннеля беречь нечего — там можно лить широко.
    final workers = isConnected ? 2 : (heavy ? 8 : 12);

    // Очередь с общим курсором, а не фиксированные группы.
    //
    // Раньше список резался на пачки по N и каждая пачка ждалась целиком. Один
    // мёртвый сервер отъедал весь таймаут (4 с), и остальные освободившиеся
    // слоты всё это время простаивали: проход по 16 конфигам растягивался на
    // десяток секунд, часть замеров не успевала и в списке оставались прочерки.
    // Теперь N работников разбирают очередь подряд: слот освободился — сразу
    // берётся следующий сервер.
    // Предел на проход при поднятом туннеле.
    //
    // Пока идёт замер, сторож туннеля молчит — проба конкурировала бы с
    // замерами и соврала. Значит, длительность прохода это и есть окно, в
    // котором обрыв никто не заметит. Сорок секунд — потолок: кого не успели,
    // сохранят прошлые значения и попадут в следующий заход.
    final deadline = isConnected
        ? DateTime.now().add(const Duration(seconds: 40))
        : null;

    var cursor = 0;
    var lastChance = false;
    final failed = <VpnServer>[];
    Future<void> worker() async {
      while (true) {
        if (deadline != null && DateTime.now().isAfter(deadline)) return;
        final i = cursor++;
        if (i >= list.length) return;
        final srv = list[i];
        final got = await _pingServer(srv,
            background: background, forceTcp: forceTcp, lastChance: lastChance);
        if (!got && !lastChance) failed.add(srv);
        if (pingSweepDone < pingSweepTotal) pingSweepDone++;
        _sweepNotify(); // значение видно сразу, но без мигания списка
      }
    }

    try {
      await Future.wait(List.generate(workers, (_) => worker()));

      // Второй заход по тем, кто не ответил.
      //
      // Первая попытка часто срывается не из-за сервера, а из-за самого прохода:
      // телефон в этот момент держит десяток соединений разом. Без повтора такой
      // конфиг оставался прочерком до следующего цикла — человек видел «мёртвый»
      // сервер, который на самом деле живой.
      final timeUp = deadline != null && DateTime.now().isAfter(deadline);
      if (!timeUp && failed.isNotEmpty && failed.length < list.length) {
        cursor = 0;
        lastChance = true; // не ответил и сейчас — значит правда недоступен
        list
          ..clear()
          ..addAll(failed);
        await Future.wait(List.generate(workers, (_) => worker()));
      }
      pingSweepEverCompleted = true;
    } finally {
      pingSweepRunning = false;
      _sweepNotify(force: true);
    }
  }

  // ---- авто-пинг для режима «Авто» ----
  Timer? _aiTimer;

  DateTime? _lastResumeSweep;

  /// Перемер списка при возврате в приложение.
  ///
  /// Пока человек был снаружи, сеть могла смениться — старые числа не значат
  /// ничего. Не чаще раза в 20 секунд: возвраты бывают частыми (свернул —
  /// развернул), и гонять полный замер на каждый незачем.
  void refreshPingsOnResume() {
    // Сбрасываем состояние сторожа ПЕРВЫМ делом, до любых проверок. Пока
    // приложение было в фоне, Android держал его таймеры остановленными, и всё,
    // что сторож успел насчитать, к текущему моменту не относится — сработав на
    // этих данных, он оборвёт живое соединение сразу после возврата.
    _healthFails = 0;
    _wdLastBytes = bytesDown;

    if (servers.isEmpty || pingSweepRunning) return;
    final now = DateTime.now();
    if (_lastResumeSweep != null &&
        now.difference(_lastResumeSweep!).inSeconds < 20) {
      return;
    }
    _lastResumeSweep = now;
    unawaited(_pingAllSilent(background: true).then((_) => _switchIfWorthIt()));
  }

  /// Насколько новый сервер должен быть быстрее текущего, чтобы имело смысл
  /// переключаться. Оба условия сразу: и в миллисекундах, и в долях.
  ///
  /// Без этого приложение прыгало между серверами на каждом замере: задержка
  /// колеблется на десятки миллисекунд сама по себе, и «лучший» всё время
  /// оказывался разным. Каждое переключение — это разрыв соединения, так что
  /// менять сервер ради выигрыша в пару миллисекунд вредно.
  static const switchGainMs = 40;
  static const switchGainRatio = 0.7;

  /// На какой сервер стоит перейти прямо сейчас. null — оставаться на текущем.
  ///
  /// Чистое решение без побочных эффектов: удобно проверять и легко читать.
  /// Правило простое — менять сервер только ради ЗАМЕТНОГО выигрыша, потому
  /// что каждое переключение рвёт соединение.
  VpnServer? bestSwitchTarget() {
    if (mode != GlobalMode.ai) return null; // ручной выбор не подменяем
    final cur = activeServer;
    if (cur == null) return null;

    final best = _bestServer();
    if (best.id == cur.id) return null;

    // Текущий признан нерабочим — уходим сразу, пороги тут ни при чём.
    if (cur.unreachable) return best;

    final c = cur.pingMs, b = best.pingMs;
    if (c <= 0 || b <= 0) return null; // нет данных — не гадаем
    final worth = (c - b) >= switchGainMs && b <= c * switchGainRatio;
    return worth ? best : null;
  }

  /// Меняет сервер, если [bestSwitchTarget] считает это оправданным.
  Future<void> _switchIfWorthIt() async {
    if (_connecting || _switching) return;
    if (!pingSweepEverCompleted) return; // ещё не всё померяно — не дёргаемся
    final cur = activeServer;
    final best = bestSwitchTarget();
    if (cur == null || best == null) return;

    // Тот же запрет, что и у сторожа: иначе они переключают по очереди и
    // соединение рвётся вдвое чаще, чем разрешено каждому из них.
    if (_reconnectedRecently) return;
    _lastAutoReconnect = DateTime.now();
    _log('Авто: ${best.title} быстрее (${best.pingMs} мс против '
        '${cur.pingMs} мс) — перехожу', LogKind.notice);
    _setAutoServer(best.id);
    if (isConnected) await _reconnectTo();
  }

  void _startAiAutoPing() {
    _aiTimer?.cancel();
    if (pingEveryS <= 0) return; // «не мерить»: авто-замер выключен
    _scheduleAiPing();
  }

  /// Назначает следующий замер — через pingEveryS ПОСЛЕ окончания предыдущего.
  ///
  /// Именно после окончания, а не по звонку периодического таймера. Полный
  /// проход по двум десяткам серверов занимает около тридцати секунд, и при
  /// интервале в те же тридцать замеры шли встык, без единого промежутка. А в
  /// это время сторож туннеля не может вынести вердикт — значит, оборванное
  /// соединение не замечал никто. Теперь между замерами всегда есть тишина,
  /// и её хватает сторожу на две проверки.
  void _scheduleAiPing() {
    _aiTimer?.cancel();
    final every = pingEveryS;
    if (every <= 0) return;
    _aiTimer = Timer(Duration(seconds: every), () async {
      try {
        if (mode == GlobalMode.ai &&
            servers.isNotEmpty &&
            !pingSweepRunning &&
            !_connecting &&
            !_switching) {
          // Меряем ВЕСЬ список: человек должен видеть, что числа живут, а
          // выбор должен опираться на свежие данные обо всех серверах.
          await _pingAllSilent(background: true);
          await _switchIfWorthIt();
        }
      } finally {
        // Назначаем следующий в любом случае: сорвавшийся замер не должен
        // останавливать авто-режим навсегда.
        if (pingEveryS > 0) _scheduleAiPing();
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
      rules =
          list.map((e) => AppRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      rules = [];
    }
  }

  void _saveRules() {
    _storage.appRulesJson = jsonEncode(rules.map((r) => r.toJson()).toList());
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
        entries.add(RouteEntry(
            appName: r.appName, serverName: 'Напрямую', direct: true));
      } else if (r.mode == RouteMode.manualServer && r.serverId != null) {
        final matches = servers.where((x) => x.id == r.serverId);
        final s = matches.isEmpty ? null : matches.first;
        entries.add(RouteEntry(
          appName: r.appName,
          serverName: s?.title ?? '—',
          serverFlag: s?.flag ?? '🌐',
        ));
      } else if (srv != null) {
        entries.add(RouteEntry(
            appName: r.appName, serverName: srv.title, serverFlag: srv.flag));
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
    // Всё, что относится к добавленным подпискам, тоже уходит: иначе после
    // перезапуска серверы восстанавливались из памяти и с диска.
    foreignSubUrls = const [];
    _foreignRaws = const [];
    _foreignBodies = {};
    foreignUntil = {};
    foreignInfo = {};
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
    _profileUsername = '';
    logs.clear();
    notifyListeners();
    _pushWidget();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _aiTimer?.cancel();
    _subRefreshTimer?.cancel();
    _subGuardTimer?.cancel();
    _connSub?.cancel();
    notice.dispose();
    vpn.dispose();
    super.dispose();
  }
}
