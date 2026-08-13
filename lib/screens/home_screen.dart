/// Главный экран Various VPN — тёмная тема, глобус-карта, кнопка-переливание,
/// переключатель ИИ/Ручной, серверы по странам с флагами и кнопкой пинга.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../models/connection_status.dart';
import '../models/vpn_server.dart';
import '../services/geo.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../theme/motion.dart';
import '../widgets/ambient_bars.dart';
import '../widgets/ios_segmented.dart';
import '../widgets/connect_button.dart';
import '../widgets/connect_ways.dart';
import '../widgets/connect_glow.dart';
import '../widgets/flag.dart';
import '../widgets/tap_scale.dart';
import '../widgets/globe.dart';
import '../widgets/session_card.dart';
import 'per_app_screen.dart';
import 'profile_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import '../widgets/streak_flame.dart';
import '../widgets/app_toast.dart';
import '../platform.dart';

/// Корневая оболочка приложения: 4 вкладки в PageView, между которыми можно
/// переключаться свайпом (Apps / Чат / Настройки) и тапом по нижней панели.
/// На вкладке-глобусе свайп страниц отключён — там горизонтальное движение
/// вращает сам глобус, поэтому уходим с неё только тапом по панели.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись в приложение — перемеряем список. Пока человек был снаружи,
    // сеть могла смениться (Wi-Fi → мобильный), и прежние числа устарели.
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshPingsOnResume();
    }
  }

  final PageController _pc = PageController();
  int _index = 0;

  /// Дробная позиция страниц — та же величина, что и у листания, только
  /// доступная панели снизу.
  ///
  /// Ради неё всё и затевалось: в Telegram подпись вкладки разгорается не в
  /// момент отпускания, а по ходу движения пальца. Страница уехала на треть —
  /// значок внизу на треть же и перекрасился. Без этого панель узнаёт о смене
  /// вкладки последней и выглядит приклеенной задним числом.
  final ValueNotifier<double> _pos = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pc.addListener(_syncPos);
  }

  void _syncPos() {
    final p = _pc.hasClients ? _pc.page : null;
    if (p != null) _pos.value = p;
  }

  void _go(int i) {
    if (i == _index) return;
    _pc.animateToPage(i,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  /// Ведение пальцем по самой панели: страницы едут следом, а не прыгают в
  /// конце. Панель и содержимое — одно движение, поэтому позицию задаём
  /// напрямую в пикселях листания.
  void _scrub(double page) {
    if (!_pc.hasClients) return;
    _pc.jumpTo(page * _pc.position.viewportDimension);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pc.removeListener(_syncPos);
    _pc.dispose();
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.isConnected;
    return Scaffold(
      backgroundColor: P.bg,
      bottomNavigationBar: _BottomBar(
        trafficLines: connected ? state.trafficLines : const [],
        showTraffic: connected,
        upKbps: state.speedUpKbps,
        downKbps: state.speedDownKbps,
        animate: state.animationsOn,
        position: _pos,
        currentIndex: _index,
        onSelect: _go,
        onScrub: _scrub,
      ),
      // Пока палец на глобусе, листание вкладок выключено. Без этого любое
      // движение вбок над глобусом улетало в PageView: страница перелистывалась,
      // а глобус слушался только движений вверх-вниз.
      body: ValueListenableBuilder<bool>(
        valueListenable: GlobeTouch.active,
        builder: (context, onGlobe, _) => PageView(
          controller: _pc,
          physics: onGlobe
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          onPageChanged: (i) => setState(() => _index = i),
          children: [
            const HomeScreen(),
            // Разделение по приложениям — только Android: система iOS не
            // отдаёт обычному приложению ни списка программ, ни выборочной
            // маршрутизации, туннель там всегда общий. Вкладку просто не
            // показываем — остаётся три.
            if (Caps.perAppRouting) const PerAppScreen(inShell: true),
            const SupportScreen(inShell: true),
            const SettingsScreen(inShell: true),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<AppState>();
    if (!identical(_state, s)) {
      _state?.notice.removeListener(_onNotice);
      _state = s;
      _state!.notice.addListener(_onNotice);
    }
  }

  void _onNotice() {
    // Плашка сверху: снизу её перекрывали панель навигации и палец. Событий
    // про смену сервера здесь уже нет — они остались только в логах, — так что
    // всё, что сюда доходит, человек и ждёт увидеть.
    final n = _state?.notice.value;
    if (n == null) return;
    _state!.notice.value = null;
    if (!mounted) return;
    AppToast.show(context, n.text,
        kind: n.error
            ? ToastKind.error
            : (n.success ? ToastKind.ok : ToastKind.info));
  }

  @override
  void dispose() {
    _state?.notice.removeListener(_onNotice);
    super.dispose();
  }

  // Маркеры серверов на глобусе — по одному на страну.
  List<GlobeMarker> _markers(AppState s) {
    final target = s.activeServer;
    final seen = <String>{};
    final out = <GlobeMarker>[];
    for (final srv in s.servers) {
      final cc = srv.countryCode;
      final ll = Geo.of(cc);
      // только распознанные страны с валидными координатами (не «нулевой остров»)
      if (cc.length != 2 || ll == null || !seen.add(cc)) continue;
      if (ll[0].abs() < 0.5 && ll[1].abs() < 0.5) continue;
      out.add(GlobeMarker(
        lon: ll[0],
        lat: ll[1],
        label: srv.countryName,
        code: cc,
        selected: target != null && target.countryCode == cc,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.isConnected;
    final connecting = state.stage == VpnStage.connecting;
    final active = state.activeServer;
    final focus = active != null ? Geo.of(active.countryCode) : null;

    return Scaffold(
      backgroundColor: P.bg,
      body: Stack(
        children: [
          Positioned.fill(
              child: AmbientBars(
                  connected: connected, animate: state.animationsOn)),
          if (state.animationsOn)
            Positioned.fill(child: ConnectGlow(connected: connected)),
          SafeArea(
            bottom: false,
            // Пока палец на глобусе, список стоит — иначе он забирает
            // вертикальный свайп и глобус не крутится. Перестраивается только
            // сам список, а не весь экран.
            child: ValueListenableBuilder<bool>(
              valueListenable: GlobeTouch.active,
              builder: (context, onGlobe, _) => ListView(
              physics: onGlobe
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
              children: [
                if (!state.online) ...[
                  const _NoInternetBanner(),
                  const SizedBox(height: 12),
                ],
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child:
                      _Header(active: active, telegramOnly: state.telegramOnly),
                ),
                const SizedBox(height: 14),
                _ModeToggle(
                  mode: state.mode,
                  onChanged: state.setMode,
                ),
                const SizedBox(height: 10),

                // --- глобус ---
                // Флаг «палец на глобусе» глобус выставляет сам (GlobeTouch),
                // здесь его только слушают. Раньше это делал Listener с
                // setState — и КАЖДОЕ касание перестраивало весь экран.
                Center(
                  child: RepaintBoundary(
                    child: GlobeView(
                      size: 264,
                      markers: _markers(state),
                      focus: focus,
                      connected: connected,
                      packetFrom: connected ? Geo.origin : null,
                      // Подпись берём из общей таблицы стран — она переводится
                      // вместе с интерфейсом.
                      packetFromLabel: countryLabel('RU'),
                      animationsEnabled: state.animationsOn,
                      // Во время замера падающих звёзд больше.
                      busy: state.pinging || state.pingSweepRunning,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // --- кнопка подключения ---
                Center(
                  child: ConnectButton(
                    connected: connected,
                    animate: state.animationsOn,
                    busy: connecting || state.busy,
                    // Без сети подключаться не к чему: раньше кнопка нажималась,
                    // крутилась и заканчивалась ошибкой. Теперь она честно
                    // говорит, чего не хватает.
                    label: !state.online && !connected
                        ? L.t('no_net_btn')
                        : connecting
                            ? L.t('connecting')
                            : connected
                                ? L.t('protected')
                                : L.t('disconnected'),
                    onTap: () {
                      if (connecting) return;
                      if (!state.online && !connected) return;
                      // Мгновенный виброотклик на нажатие (не ждём исход коннекта).
                      if (state.vibrationEnabled) {
                        HapticFeedback.mediumImpact();
                        HapticFeedback.vibrate();
                      }
                      if (connected) {
                        state.disconnect();
                      } else if (state.telegramOnly) {
                        // Бесплатный режим: поднимаем именно Telegram-only туннель,
                        // а не полный (иначе через VPN пойдёт весь трафик).
                        state.connectTelegramOnly();
                      } else {
                        state.connect();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 6),

                // Карточка сессии плавно раскрывается при подключении (fade + size),
                // а не появляется рывком.
                AnimatedSize(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedOpacity(
                    opacity: connected ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: connected
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: SessionCard(
                              duration: state.sessionDuration,
                              bytesDown: state.bytesDown,
                              bytesUp: state.bytesUp,
                              speedDownKbps: state.speedDownKbps,
                              speedUpKbps: state.speedUpKbps,
                              history: state.speedHistory,
                              historyUp: state.speedHistoryUp,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ),

                // В бесплатном режиме — карточка «пробный доступ · только Telegram»
                // в нашем стиле (с ∞ трафика и статусом подключения), вместо обычной.
                if (state.telegramOnly) ...[
                  _FreeStatusCard(
                    connected: connected,
                    connecting: connecting,
                    server: active,
                  ),
                  const SizedBox(height: 10),
                ] else if (state.subLoaded &&
                    (state.subActive || state.subUntil != null)) ...[
                  // Статус берём ТОЛЬКО из подписки. Наличие серверов доступом не
                  // является: панель отдаёт список всем, и раньше из-за hasServers
                  // неоплативший видел «Подписка активна» и не получал предложения
                  // купить.
                  _SubscriptionCard(
                    active: state.subActive,
                    until: state.subUntil,
                    serverCount: state.servers.length,
                  ),
                  const SizedBox(height: 10),
                ],

                // «Уже есть подписка?» — только когда подписки НЕТ вообще.
                // Раньше плашка висела и у того, кто только что добавил свою:
                // приложение как будто не заметило её и продолжало продавать.
                if (!state.subActive && !state.hasForeignServers) ...[
                  const _SubActionsCard(),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 4),
                _ServersSection(state: state),
              ],
              ),
            ),
          ),
          // празднование награды за серию (огонёк) — поверх всего
          if (state.celebrateMilestone > 0)
            Positioned.fill(
              child: StreakCelebration(
                milestone: state.celebrateMilestone,
                rewardDays: state.celebrateRewardDays,
                onClose: state.clearCelebration,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- шапка ----------

class _Header extends StatelessWidget {
  final VpnServer? active;
  final bool telegramOnly;
  const _Header({required this.active, required this.telegramOnly});

  @override
  Widget build(BuildContext context) {
    final cc = active?.countryCode ?? '';
    // Берём ТО ЖЕ имя, что показано в списке (title), а не название страны.
    // Иначе у серверов вроде «Обход БС #9» шапка и список писали разное про
    // один и тот же сервер, и выглядело это как рассинхрон.
    final name = telegramOnly
        ? L.t('free_tg')
        : (active?.title ?? L.t('no_server'));
    final sub = telegramOnly
        ? L.t('free_tg_sub')
        : (active != null ? active!.transportLabel : L.t('import_hint'));
    final ping =
        active != null && active!.pingMs > 0 ? '${active!.pingMs} ms' : '—';

    return Row(
      children: [
        if (cc.isNotEmpty)
          CountryFlag(cc)
        else
          const Icon(Icons.public, size: 20, color: P.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: P.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Text(sub,
                  style: const TextStyle(color: P.textFaint, fontSize: 11)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(ping,
                style: const TextStyle(
                    color: P.limeText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            Text(L.t('ping'),
                style: const TextStyle(color: P.textFaint, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

// ---------- переключатель режима ----------

/// Красивый баннер «нет интернета» — показывается вверху главного экрана, когда
/// у телефона нет сети (VPN без интернета не заработает).
class _NoInternetBanner extends StatelessWidget {
  const _NoInternetBanner();

  @override
  Widget build(BuildContext context) {
    const warn = Color(0xFFE2A24A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warn.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: warn.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_off_rounded, color: warn, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('no_net_title'),
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(L.t('no_net_body'),
                    style: const TextStyle(color: P.textDim, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final GlobalMode mode;
  final ValueChanged<GlobalMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Раньше переключалось рывком по взмаху: пока палец не оторвёшь —
        // ничего не происходит, а потом сегмент перекрашивается скачком.
        // Теперь таблетка едет ЗА пальцем и доводится пружиной, как в iOS.
        IosSegmented<GlobalMode>(
          value: mode,
          onChanged: onChanged,
          items: [
            (GlobalMode.ai, L.t('ai_auto')),
            (GlobalMode.manual, L.t('manual')),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          mode == GlobalMode.ai ? L.t('mode_hint_ai') : L.t('mode_hint_manual'),
          style: const TextStyle(color: P.textFaint, fontSize: 11),
        ),
      ],
    );
  }
}

// ---------- секция серверов ----------

class _ServersSection extends StatelessWidget {
  final AppState state;
  const _ServersSection({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.hasServers) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServersScreen()),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(L.t('servers'),
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, color: P.textFaint, size: 18),
              ]),
            ),
            // Кнопок в строке стало больше (вид списка + обновить + пинг), и на
            // узких экранах она перестала помещаться. Ужимаем группу по месту,
            // а не ломаем вёрстку.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Вид списка серверов: сетка по два в ряд ↔ полный список.
              //
              // Раньше это была ОДНА кнопка с иконкой того вида, куда
              // переключишься. Её стабильно читали наоборот — как текущий вид,
              // — и переключение казалось перепутанным. Теперь видно сразу оба
              // варианта, и подсвечен тот, который включён: спутать нечего.
              _ViewModeToggle(
                compact: state.compactServers,
                onChanged: state.setCompactServers,
              ),
              TapScale(
                // Ответ на нажатие приходит плашкой сверху из
                // refreshSubscription: и «список обновлён», и причина отказа.
                onTap: state.busy ? null : state.refreshSubscription,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border:
                        Border.all(color: P.textFaint.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    state.busy && !state.pinging
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: P.textFaint))
                        : const Icon(Icons.refresh,
                            size: 15, color: P.textFaint),
                    const SizedBox(width: 5),
                    Text(L.t('update_short'),
                        style:
                            const TextStyle(color: P.textFaint, fontSize: 12)),
                  ]),
                ),
              ),
              TapScale(
                onTap: state.busy || state.pingSweepRunning
                    ? null
                    : state.pingAll,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: P.lime.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    state.busy || state.pingSweepRunning
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: P.limeText))
                        : const Icon(Icons.radar, size: 14, color: P.limeText),
                    const SizedBox(width: 5),
                    // Во время замера показываем прогресс «7 / 15». Без этого
                    // фоновый замер был совершенно незаметен, и казалось, что
                    // авто-режим ничего не делает.
                    Text(
                        state.pingSweepRunning
                            ? '${state.pingSweepDone}/${state.pingSweepTotal}'
                            : L.t('ping_btn'),
                        style:
                            const TextStyle(color: P.limeText, fontSize: 12)),
                  ]),
                ),
              ),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Папки серверов (Все / WiFi / Мобильный интернет …) — фильтр списка.
        if (!state.telegramOnly) _FolderChips(state: state),
        // Внутри конкретной папки — кнопка «Добавить серверы» (отметить, какие
        // конфиги входят в папку).
        if (!state.telegramOnly && state.activeFolder.isNotEmpty) ...[
          _AddToFolderButton(
            onTap: () => _showAddServersToFolder(context, state),
          ),
          const SizedBox(height: 8),
        ],
        // Бесплатный режим: активен ТОЛЬКО авто-конфиг для Telegram (сам подбирает
        // рабочий сервер). Остальные конфиги показываем тускло и некликабельно —
        // чтобы было видно: они появятся с подпиской, но сейчас не работают.
        if (state.telegramOnly)
          Column(
            children: [
              _AutoTelegramRow(server: state.activeServer),
              const SizedBox(height: 8),
              for (final s in state.servers)
                _ServerRow(
                  key: ValueKey(s.id),
                  server: s,
                  active: false,
                  locked: true,
                  onTap: () => showFreeLockedDialog(context),
                ),
            ],
          )
        else if (state.visibleServers.isEmpty)
          // Пустая папка — подсказка вместо голого места.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(L.t('folder_empty'),
                  style: const TextStyle(color: P.textFaint, fontSize: 12.5)),
            ),
          )
        else
          // Свайп влево/вправо по области списка — переключение папок по кругу.
          _FolderSwipe(
            state: state,
            child: state.compactServers
                ? _CompactGrid(state: state)
                : _FullList(state: state),
          ),
      ],
    );
  }

  /// Лист выбора серверов для текущей папки: галочками отмечаем, какие конфиги
  /// входят в [state.activeFolder]. Тап по строке — вкл/выкл членство.
  static void _showAddServersToFolder(BuildContext context, AppState state) {
    final folder = state.activeFolder;
    if (folder.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: P.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Row(children: [
                    const Icon(Icons.folder_open, color: P.limeText, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${L.t('folder_pick_servers')} · $folder',
                          style: const TextStyle(
                              color: P.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in state.servers)
                        CheckboxListTile(
                          value: state.folderOf(s.id) == folder,
                          activeColor: P.lime,
                          checkColor: P.onLime,
                          controlAffinity: ListTileControlAffinity.trailing,
                          title: Row(children: [
                            CountryFlag(
                                s.countryCode.isEmpty ? '??' : s.countryCode,
                                width: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: P.text)),
                            ),
                          ]),
                          onChanged: (v) {
                            state.setServerFolder(
                                s.id, v == true ? folder : null);
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(L.t('save')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showFolderPicker(
      BuildContext context, AppState state, VpnServer s) {
    final current = state.folderOf(s.id) ?? '';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(children: [
                Text(L.t('srv_move_folder'),
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            ListTile(
              leading:
                  const Icon(Icons.layers_clear_outlined, color: P.textFaint),
              title: Text(L.t('folder_none'),
                  style: const TextStyle(color: P.text)),
              trailing: current.isEmpty
                  ? const Icon(Icons.check, color: P.lime)
                  : null,
              onTap: () {
                state.setServerFolder(s.id, null);
                Navigator.pop(context);
              },
            ),
            for (final f in state.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined, color: P.limeText),
                title: Text(f, style: const TextStyle(color: P.text)),
                trailing: current == f
                    ? const Icon(Icons.check, color: P.lime)
                    : null,
                onTap: () {
                  state.setServerFolder(s.id, f);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static void _showRenameDialog(
      BuildContext context, AppState state, VpnServer s) {
    final ctrl = TextEditingController(text: s.title);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('srv_rename'), style: const TextStyle(color: P.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: P.text),
          decoration: InputDecoration(
            hintText: s.countryName,
            hintStyle: const TextStyle(color: P.textFaint),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              state.renameServer(s.id, ctrl.text);
              Navigator.pop(context);
            },
            child: Text(L.t('save')),
          ),
        ],
      ),
    );
  }

  static void _confirmDelete(
      BuildContext context, AppState state, VpnServer s) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('srv_delete_q'), style: const TextStyle(color: P.text)),
        content: Text('${s.flag} ${s.title}',
            style: const TextStyle(color: P.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () {
              state.removeServer(s.id);
              Navigator.pop(context);
            },
            child: Text(L.t('delete')),
          ),
        ],
      ),
    );
  }
}

/// Свайп влево/вправо по области серверов — переключение папок по кругу.
class _FolderSwipe extends StatelessWidget {
  final AppState state;
  final Widget child;
  const _FolderSwipe({required this.state, required this.child});

  @override
  Widget build(BuildContext context) {
    if (state.folders.isEmpty) return child; // некуда переключаться
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -150) {
          state.cycleFolder(1);
        } else if (v > 150) {
          state.cycleFolder(-1);
        }
      },
      child: child,
    );
  }
}

/// Компактная сетка серверов (2 в ряд). В папке «Все» — перетаскивание
/// долгим нажатием (порядок сохраняется).
/// Переключатель вида списка серверов: сетка ↔ полный список.
///
/// Показывает оба варианта сразу и подсвечивает включённый — так не остаётся
/// вопроса «эта иконка про текущий вид или про тот, куда я перейду».
class _ViewModeToggle extends StatelessWidget {
  final bool compact;
  final ValueChanged<bool> onChanged;
  const _ViewModeToggle({required this.compact, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(IconData icon, bool mine, String tip) {
      final on = mine == compact;
      return Tooltip(
        message: tip,
        child: TapScale(
          onTap: on ? null : () => onChanged(mine),
          child: AnimatedContainer(
            duration: M.state,
            curve: M.standard,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: on ? P.lime.withValues(alpha: 0.16) : Colors.transparent,
            ),
            child: Icon(icon,
                size: 15, color: on ? P.limeText : P.textFaint),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: P.textFaint.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(Icons.grid_view_rounded, true, L.t('view_grid')),
        seg(Icons.view_agenda_outlined, false, L.t('view_list')),
      ]),
    );
  }
}


class _CompactGrid extends StatelessWidget {
  final AppState state;
  const _CompactGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    final list = state.visibleServers;
    final canDrag = state.activeFolder.isEmpty; // порядок меняем только в «Все»
    final w = (MediaQuery.of(context).size.width - 18 * 2 - 8) / 2;

    Widget cellFor(VpnServer s) => _CompactServerCell(
          server: s,
          locked: _locked(state, s),
          active: state.activeServer?.id == s.id && !_locked(state, s),
          onTap: _tapFor(context, state, s),
          onRename: () => _ServersSection._showRenameDialog(context, state, s),
          onDelete: () => _ServersSection._confirmDelete(context, state, s),
          onFolder: () => _ServersSection._showFolderPicker(context, state, s),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in list)
          if (!canDrag)
            cellFor(s)
          else
            DragTarget<String>(
              onWillAcceptWithDetails: (d) => d.data != s.id,
              onAcceptWithDetails: (d) => state.moveServer(d.data, s.id),
              builder: (context, cand, rej) {
                final hovering = cand.isNotEmpty;
                return LongPressDraggable<String>(
                  data: s.id,
                  // Короче стандартных 500 мс — перетаскивание начинается легче.
                  delay: const Duration(milliseconds: 180),
                  onDragStarted: () {
                    HapticFeedback.mediumImpact();
                    state.setListDragging(true);
                  },
                  onDragEnd: (_) => state.setListDragging(false),
                  onDraggableCanceled: (_, __) => state.setListDragging(false),
                  // Лёгкий подъём (scale 1.03), прозрачный Material, без тени —
                  // тот же вид, что и у строк полного списка.
                  feedback: Transform.scale(
                    scale: 1.03,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      child: SizedBox(width: w, child: cellFor(s)),
                    ),
                  ),
                  childWhenDragging: Opacity(opacity: 0.25, child: cellFor(s)),
                  // foregroundDecoration рисует рамку-подсветку ПОВЕРХ ячейки,
                  // не меняя её размер — иначе 2 в ряд «съезжают» в 1.
                  child: Container(
                    foregroundDecoration: hovering
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: P.lime, width: 2),
                          )
                        : null,
                    child: cellFor(s),
                  ),
                );
              },
            ),
      ],
    );
  }
}

/// Полный список серверов (по одному в ряд). В папке «Все» — перетаскивание
/// долгим нажатием через ReorderableListView.
/// Заблокирован ли сервер: нет НАШЕЙ подписки, а сервер — наш.
///
/// Конфиги чужой подписки не блокируются никогда: приложение для них — обычный
/// VPN-клиент, продавать там нечего.
bool _locked(AppState state, VpnServer s) => !state.hasAccess && !s.foreign;

/// Что делает тап по серверу: выбирает его или зовёт оформить подписку.
VoidCallback _tapFor(BuildContext context, AppState state, VpnServer s) {
  if (_locked(state, s)) return () => showFreeLockedDialog(context);
  return () {
    state.setManualServer(s.id);
    if (state.mode != GlobalMode.manual) state.setMode(GlobalMode.manual);
  };
}

class _FullList extends StatelessWidget {
  final AppState state;
  const _FullList({required this.state});

  @override
  Widget build(BuildContext context) {
    final list = state.visibleServers;
    Widget rowFor(VpnServer s) => _ServerRow(
          key: ValueKey(s.id),
          server: s,
          locked: _locked(state, s),
          active: state.activeServer?.id == s.id && !_locked(state, s),
          onTap: _tapFor(context, state, s),
          onRename: () => _ServersSection._showRenameDialog(context, state, s),
          onDelete: () => _ServersSection._confirmDelete(context, state, s),
          onFolder: () => _ServersSection._showFolderPicker(context, state, s),
        );

    if (state.activeFolder.isNotEmpty) {
      return Column(children: [for (final s in list) rowFor(s)]);
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // onReorderItem, а не устаревший onReorder: он сам вносит поправку на
      // уже вынутый элемент, и та же логика перестановки живёт в состоянии.
      onReorderItem: state.reorderServers,
      // Пока карточку тащат, фоновый замер не должен перерисовывать список:
      // каждая перерисовка срывала захват, и переставить конфиг было нельзя.
      onReorderStart: (_) => state.setListDragging(true),
      onReorderEnd: (_) => state.setListDragging(false),
      // Убираем дефолтную синеватую Material-тень при перетаскивании — вместо неё
      // мягкий подъём карточки (scale) без постороннего свечения.
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, ch) {
          final t = Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: 1 + 0.03 * t,
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              child: ch,
            ),
          );
        },
        child: child,
      ),
      children: [
        // Тащим за саму карточку, удержанием — так это и ожидается от списка.
        for (var i = 0; i < list.length; i++)
          ReorderableDelayedDragStartListener(
            key: ValueKey(list[i].id),
            index: i,
            child: rowFor(list[i]),
          ),
      ],
    );
  }
}

/// Ряд папок серверов: «Все» + пользовательские (WiFi / Мобильный интернет …) + ＋.
class _FolderChips extends StatelessWidget {
  final AppState state;
  const _FolderChips({required this.state});

  Widget _chip(String label, bool active, VoidCallback onTap,
      {VoidCallback? onLong, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onLongPress: onLong,
        child: TapScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? P.lime.withValues(alpha: 0.16) : P.surfaceLo,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active ? P.lime : P.surfaceHi,
                  width: active ? 1 : 0.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: active ? P.limeText : P.textFaint),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      color: active ? P.limeText : P.textDim,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('folder_new'), style: const TextStyle(color: P.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: P.text),
          decoration: InputDecoration(
            hintText: L.t('folder_hint'),
            hintStyle: const TextStyle(color: P.textFaint),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text(L.t('save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      state.addFolder(name);
      state.setActiveFolder(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip(L.t('folder_all'), state.activeFolder.isEmpty,
              () => state.setActiveFolder(''),
              icon: Icons.dns_outlined),
          for (final f in state.folders)
            _chip(f, state.activeFolder == f, () => state.setActiveFolder(f),
                onLong: () => _confirmRemoveFolder(context, f)),
          _chip(L.t('folder_add'), false, () => _addFolder(context),
              icon: Icons.add),
        ]),
      ),
    );
  }

  void _confirmRemoveFolder(BuildContext context, String name) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title:
            Text(L.t('folder_delete_q'), style: const TextStyle(color: P.text)),
        content: Text(name, style: const TextStyle(color: P.textDim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () {
              state.removeFolder(name);
              Navigator.pop(context);
            },
            child: Text(L.t('delete')),
          ),
        ],
      ),
    );
  }
}

/// Кнопка «Добавить серверы» внутри папки.
class _AddToFolderButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddToFolderButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: P.lime.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: P.lime.withValues(alpha: 0.5),
              width: 1,
              style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 18, color: P.limeText),
            const SizedBox(width: 8),
            Text(L.t('folder_add_servers'),
                style: const TextStyle(
                    color: P.limeText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Активный авто-конфиг Telegram (в бесплатном режиме) — единственный рабочий.
class _AutoTelegramRow extends StatelessWidget {
  final VpnServer? server;
  const _AutoTelegramRow({required this.server});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: P.lime.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.lime, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: P.lime.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.auto_awesome, color: P.limeText, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(L.t('free_auto_title'),
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(
                  server != null
                      ? '${L.t('free_auto_sub')} · ${server!.title}'
                      : L.t('free_auto_sub'),
                  style: const TextStyle(color: P.limeText, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: P.lime, size: 18),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  final VpnServer server;
  final bool active;
  final bool
      locked; // бесплатный режим: сервер недоступен (тусклый, по тапу — апселл)
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onFolder;

  const _ServerRow(
      {super.key,
      required this.server,
      required this.active,
      this.locked = false,
      required this.onTap,
      this.onRename,
      this.onDelete,
      this.onFolder});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: active ? P.lime.withValues(alpha: 0.08) : P.surfaceLo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? P.lime : P.surfaceHi, width: active ? 1 : 0.5),
      ),
      child: Row(
        children: [
          CountryFlag(server.countryCode.isEmpty ? '??' : server.countryCode),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.title,
                    style: const TextStyle(color: P.text, fontSize: 13)),
                Text(server.transportLabel,
                    style: const TextStyle(color: P.textFaint, fontSize: 10)),
              ],
            ),
          ),
          if (context.watch<AppState>().pinging)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: P.limeText)),
            )
          else ...[
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Пороги «хорошо/средне/плохо» зависят от МЕТОДА: у точного
                  // замера числа больше. Берём метод из самого сервера — при
                  // настройке брались бы чужие пороги, если конкретный сервер
                  // померян иначе.
                  color: P.pingColor(server.pingMs,
                      proxy: server.pingVia == 'proxy')),
            ),
            Text(
              server.pingMs > 0 ? '${server.pingMs} ms' : '—',
              style: TextStyle(
                  color: active ? P.limeText : P.textFaint, fontSize: 12),
            ),
          ],
          if (active) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_circle, color: P.lime, size: 18),
          ],
          if (locked) ...[
            const SizedBox(width: 6),
            const Icon(Icons.lock_outline, color: P.textFaint, size: 15),
          ],
          // Замер пинга именно этого сервера. Общий замер по всему списку идёт
          // секунды, а проверить обычно нужен один конкретный: ожил или нет.
          if (!locked) _PingButton(server: server),
          // ⋮ — переименовать / удалить (не в бесплатном режиме).
          if (!locked && (onRename != null || onDelete != null))
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: P.textFaint, size: 20),
              color: P.surface,
              padding: EdgeInsets.zero,
              onSelected: (v) {
                if (v == 'rename') onRename?.call();
                if (v == 'folder') onFolder?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined, size: 18, color: P.text),
                    const SizedBox(width: 10),
                    Text(L.t('srv_rename'),
                        style: const TextStyle(color: P.text)),
                  ]),
                ),
                if (onFolder != null)
                  PopupMenuItem(
                    value: 'folder',
                    child: Row(children: [
                      const Icon(Icons.folder_outlined,
                          size: 18, color: P.text),
                      const SizedBox(width: 10),
                      Text(L.t('srv_move_folder'),
                          style: const TextStyle(color: P.text)),
                    ]),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_outline, size: 18, color: P.danger),
                    const SizedBox(width: 10),
                    Text(L.t('delete'),
                        style: const TextStyle(color: P.danger)),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
    // В заблокированном виде — тусклый и «как будто не работает», по тапу апселл.
    if (locked) {
      return Opacity(
        opacity: 0.38,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: row,
        ),
      );
    }
    return TapScale(onTap: onTap, child: row);
  }
}


/// Кнопка «померить пинг» рядом с одним конфигом.
///
/// Пока идёт замер — на её месте крутится спиннер. Состояние берётся из
/// AppState по id сервера, поэтому кнопка честно показывает работу и не даёт
/// запустить второй замер того же сервера.
class _PingButton extends StatelessWidget {
  final VpnServer server;
  final bool compact;
  const _PingButton({required this.server, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy = state.pingingIds.contains(server.id);
    final size = compact ? 15.0 : 17.0;
    return Tooltip(
      message: L.t('srv_ping_one'),
      child: TapScale(
        onTap: busy ? null : () => state.pingOne(server),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 5),
          child: busy
              ? SizedBox(
                  width: size,
                  height: size,
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: P.limeText),
                )
              : Icon(Icons.network_ping, size: size, color: P.textFaint),
        ),
      ),
    );
  }
}

/// Компактная ячейка сервера (2 в ряд): флаг + страна + пинг + ⋮.
class _CompactServerCell extends StatelessWidget {
  final VpnServer server;
  final bool active;

  /// Сервер закрыт до оплаты: тусклый, по тапу — предложение подписки.
  /// Раньше этого признака у компактной ячейки не было, и без подписки список
  /// приходилось рисовать отдельной веткой — которая молча игнорировала выбор
  /// вида, из-за чего переключатель «не работал».
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onFolder;

  const _CompactServerCell({
    required this.server,
    required this.active,
    required this.onTap,
    this.locked = false,
    this.onRename,
    this.onDelete,
    this.onFolder,
  });

  @override
  Widget build(BuildContext context) {
    // 2 ячейки в ряд: (ширина контента − отступ) / 2. Отступы ListView = 18.
    final w = (MediaQuery.of(context).size.width - 18 * 2 - 8) / 2;
    return SizedBox(
      width: w,
      // Заблокированная ячейка — тусклая и без «пружинки» нажатия, ровно как
      // строка в полном списке: вид должен читаться одинаково в обоих режимах.
      child: Opacity(
        opacity: locked ? 0.38 : 1,
        child: TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 2, 8),
          decoration: BoxDecoration(
            color: active ? P.lime.withValues(alpha: 0.08) : P.surfaceLo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? P.lime : P.surfaceHi, width: active ? 1 : 0.5),
          ),
          child: Row(children: [
            CountryFlag(server.countryCode.isEmpty ? '??' : server.countryCode,
                width: 20),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(server.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: P.text, fontSize: 12.5)),
                  context.watch<AppState>().pinging
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: P.limeText))
                      : Row(children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    P.pingColor(server.pingMs,
                                        proxy: server.pingVia == 'proxy')),
                          ),
                          // Flexible: ячейка узкая, и после появления ручки
                          // перетаскивания строка с пингом перестала влезать.
                          // Обрезать число лучше, чем ломать вёрстку.
                          Flexible(
                            child: Text(
                                server.pingMs > 0 ? '${server.pingMs} ms' : '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: active ? P.limeText : P.textFaint,
                                    fontSize: 11)),
                          ),
                        ]),
                ],
              ),
            ),
            if (!locked) _PingButton(server: server, compact: true),
            if (!locked)
            SizedBox(
              width: 26,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: P.textFaint, size: 18),
                color: P.surface,
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'rename') onRename?.call();
                  if (v == 'folder') onFolder?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        const Icon(Icons.edit_outlined,
                            size: 18, color: P.text),
                        const SizedBox(width: 10),
                        Text(L.t('srv_rename'),
                            style: const TextStyle(color: P.text)),
                      ])),
                  PopupMenuItem(
                      value: 'folder',
                      child: Row(children: [
                        const Icon(Icons.folder_outlined,
                            size: 18, color: P.text),
                        const SizedBox(width: 10),
                        Text(L.t('srv_move_folder'),
                            style: const TextStyle(color: P.text)),
                      ])),
                  PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline,
                            size: 18, color: P.danger),
                        const SizedBox(width: 10),
                        Text(L.t('delete'),
                            style: const TextStyle(color: P.danger)),
                      ])),
                ],
              ),
            ),
          ]),
        ),
        ),
      ),
    );
  }
}

// ---------- карточка бесплатного (пробного) доступа · только Telegram ----------

/// Меню активации полного доступа — единая точка «как купить/подключить».
/// Открывается по кнопке в карточке бесплатного режима и из быстрых действий.
void showActivateSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: P.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      Widget row(IconData icon, String title, String sub, VoidCallback onTap,
          {bool primary = false}) {
        return TapScale(
          onTap: () {
            Navigator.pop(ctx);
            onTap();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: primary ? P.grad : null,
              color: primary ? null : P.surfaceLo,
              borderRadius: BorderRadius.circular(16),
              border: primary ? null : Border.all(color: P.surfaceHi),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      primary ? P.onLimeGhost : P.lime.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: primary ? P.onLime : P.limeText, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: primary ? P.onLime : P.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            color: primary ? P.onLimeDim : P.textFaint,
                            fontSize: 12,
                            height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: primary ? P.onLime : P.textFaint),
            ]),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.workspace_premium,
                    color: P.limeText, size: 22),
                const SizedBox(width: 8),
                Text(L.t('act_title'),
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(L.t('act_sub'),
                    style: const TextStyle(color: P.textFaint, fontSize: 12.5)),
              ),
              const SizedBox(height: 14),
              row(
                  Icons.workspace_premium,
                  L.t('act_get_bot'),
                  L.t('act_get_bot_d'),
                  () => launchUrl(Uri.parse(Brand.bot),
                      mode: LaunchMode.externalApplication),
                  primary: true),
              const SizedBox(height: 6),
              // Дальше — ТОТ ЖЕ блок, что на экране входа и в инструкции:
              // ID главным, ссылка и QR альтернативами. Раньше здесь были
              // пять равнозначных строк, и человек выбирал вместо действия.
              ConnectWays(
                compact: true,
                onSuccess: () => Navigator.of(ctx).maybePop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FreeStatusCard extends StatelessWidget {
  final bool connected;
  final bool connecting;
  final VpnServer? server;
  const _FreeStatusCard({
    required this.connected,
    required this.connecting,
    required this.server,
  });

  @override
  Widget build(BuildContext context) {
    final accent = connected ? P.lime : (connecting ? P.gold : P.textFaint);
    final statusText = connected
        ? L.t('free_connected')
        : (connecting ? L.t('connecting') : L.t('free_off'));
    // Имя берём РОВНО то же, что в списке ниже (`title`). Раньше в шапке стояло
    // название страны, а в списке — имя конфига: у подписок с несколькими
    // конфигами на одну страну выходило, что сверху «Германия», а отмечен
    // «Автовыбор | Wi-Fi 4», и это читалось как выбор не того сервера.
    final srvName = server?.title ?? '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            P.lime.withValues(alpha: 0.10),
            P.violet.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(connected ? Icons.verified : Icons.telegram,
                size: 18, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(statusText,
                  style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: P.lime.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(L.t('free_only_tg'),
                  style: const TextStyle(color: P.limeText, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _SubMetric(
                icon: Icons.dns_outlined,
                label: L.t('free_server_label'),
                value: srvName,
              ),
            ),
            Container(width: 0.5, height: 30, color: P.surfaceHi),
            Expanded(
              child: _SubMetric(
                icon: Icons.all_inclusive,
                label: L.t('traffic'),
                value: '∞',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Апселл: по тапу — меню активации полного доступа (QR / Telegram /
          // ссылка-ID / буфер / бот). Понятно, как купить и подключить.
          GestureDetector(
            onTap: () => showActivateSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: P.grad,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.workspace_premium,
                      color: P.onLime, size: 18),
                  const SizedBox(width: 8),
                  Text(L.t('free_buy_full'),
                      style: const TextStyle(
                          color: P.onLime,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- карточка подписки ----------

class _SubscriptionCard extends StatelessWidget {
  final bool active;
  final DateTime? until;
  final int serverCount;
  const _SubscriptionCard({
    required this.active,
    required this.until,
    required this.serverCount,
  });

  int? get _daysLeft => until?.difference(DateTime.now()).inDays;

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft;
    final ok = active && (days == null || days >= 0);
    final accent = ok ? P.lime : P.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified : Icons.error_outline,
                  size: 18, color: accent),
              const SizedBox(width: 8),
              Text(ok ? L.t('sub_active') : L.t('sub_inactive'),
                  style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Spacer(),
              if (days != null && days >= 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$days ${L.t('days_short')}',
                      style: TextStyle(color: accent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SubMetric(
                  icon: Icons.event,
                  label: L.t('valid_until'),
                  value: until != null ? L.date(until!) : '—',
                ),
              ),
              Container(width: 0.5, height: 30, color: P.surfaceHi),
              Expanded(
                child: _SubMetric(
                  icon: Icons.dns_outlined,
                  label: L.t('servers_label'),
                  value: '$serverCount',
                ),
              ),
            ],
          ),

          // ПРОДЛЕНИЕ — самая дешёвая конверсия из всех: человек уже платил и
          // ему уже нравится. Раньше подписка просто молча заканчивалась, и
          // он узнавал об этом, когда VPN переставал работать. Теперь за три
          // дня до конца прямо в главной карточке появляется кнопка.
          if (days != null && days <= 3) ...[
            const SizedBox(height: 12),
            TapScale(
              onTap: () => launchUrl(Uri.parse(Brand.bot),
                  mode: LaunchMode.externalApplication),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: P.grad,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.autorenew_rounded,
                        size: 18, color: P.onLime),
                    const SizedBox(width: 8),
                    Text(L.t('renew_cta'),
                        style: const TextStyle(
                            color: P.onLime,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              days < 0
                  ? L.t('renew_over')
                  : (days == 0
                      ? L.t('renew_today')
                      : L.t('renew_soon', {'n': days, 'd': L.days(days)})),
              textAlign: TextAlign.center,
              style: const TextStyle(color: P.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SubMetric(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 13, color: P.textFaint),
          const SizedBox(width: 5),
          // Длинная подпись («Действует до») в узкой половине карточки не
          // помещалась — обрезаем, а не ломаем строку.
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: P.textFaint, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 3),
        // Значение (дата или «1.7 / 110 ГБ») тоже бывает длинным. Уменьшаем
        // кегль по месту вместо переполнения — читать всё равно можно.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Быстрые действия с подпиской на главном экране (вставить ссылку / привязать TG).
class _SubActionsCard extends StatelessWidget {
  const _SubActionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: P.surfaceHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.workspace_premium, size: 18, color: P.limeText),
            const SizedBox(width: 8),
            Text(L.t('sub_actions_title'),
                style: const TextStyle(
                    color: P.text, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(L.t('sub_actions_sub'),
              style: const TextStyle(color: P.textFaint, fontSize: 12)),
          const SizedBox(height: 12),
          // Единая схема подключения (ID → ссылка/QR) — та же, что везде.
          const ConnectWays(compact: true),
        ],
      ),
    );
  }
}

// ---------- нижняя панель: трафик + табы ----------

class _BottomBar extends StatefulWidget {
  final List<String> trafficLines;
  final bool showTraffic;
  final double upKbps;
  final double downKbps;
  final bool animate;

  /// Дробная позиция листания страниц. Панель ничего не считает сама —
  /// подсветка целиком повторяет то, что делает содержимое.
  final ValueListenable<double> position;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Ведение пальцем по панели: просим страницы встать на эту позицию.
  final ValueChanged<double> onScrub;

  const _BottomBar({
    required this.trafficLines,
    required this.showTraffic,
    required this.upKbps,
    required this.downKbps,
    required this.position,
    required this.currentIndex,
    required this.onSelect,
    required this.onScrub,
    this.animate = true,
  });

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  /// Пока панель ведут пальцем, подсветка светится ярче и капсула чуть шире —
  /// видно, что элемент «взят в руку», а не просто перекрасился.
  bool _dragging = false;
  int _lastHaptic = 0;

  @override
  Widget build(BuildContext context) {
    // Нижнюю безопасную зону добавляем сами, а не через SafeArea. У SafeArea
    // всё или ничего: на телефонах с жестовой полосой она отдаёт под неё 34
    // точки, и под панелью зияет пустая полоса чуть ли не в палец высотой.
    // Полоса системная, рисовать в ней нельзя, но и отступать от неё ЕЩЁ раз
    // незачем — она сама и есть отступ. Оставляем небольшой зазор, чтобы
    // значки не упирались в неё вплотную.
    final safe = MediaQuery.of(context).padding.bottom;
    final navInner = Padding(
      padding: EdgeInsets.fromLTRB(8, 6, 8, safe > 0 ? safe - 12 : 8),
      child: _navRow(context),
    );
    final nav = Container(
      decoration: const BoxDecoration(
        color: P.surface,
        border: Border(top: BorderSide(color: P.surfaceHi)),
      ),
      child: navInner,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTraffic)
          _TrafficBar(lines: widget.trafficLines, upKbps: widget.upKbps, downKbps: widget.downKbps),
        nav,
      ],
    );
  }

  /// Значки вкладок. Их столько же, сколько страниц: на iOS вкладки
  /// «Приложения» нет, и панель обязана быть из трёх кнопок, иначе подсветка
  /// уезжает мимо.
  static List<IconData> get _icons => [
        Icons.public,
        if (Caps.perAppRouting) Icons.apps,
        Icons.chat_bubble_outline,
        Icons.settings_outlined,
      ];

  Widget _navRow(BuildContext context) {
    final n = _icons.length;
    return LayoutBuilder(builder: (context, c) {
      final slot = c.maxWidth / n;
      // Капсула по значку, а не по доле от ширины. Раньше было «две трети
      // ячейки»: на четырёх вкладках выходило нормально, а на трёх ячейка
      // шире — и капсула растянулась в лепёшку вокруг маленького значка.
      final pillW = slot < 76 ? slot - 8 : 68.0;

      /// Отклик на пересечении границы, а не при отпускании: палец понимает,
      /// что перешёл на соседнюю вкладку, ещё до того как посмотрел.
      void haptic(double pos) {
        final near = pos.round();
        if (near != _lastHaptic) {
          _lastHaptic = near;
          HapticFeedback.selectionClick();
        }
      }

      void moveTo(double dx) {
        final pos = ((dx / slot) - 0.5).clamp(0.0, (n - 1) * 1.0);
        haptic(pos);
        // Панель не двигает подсветку сама: она просит страницы встать на эту
        // позицию, а подсветка приедет следом — тем же путём, что и при
        // обычном листании. Иначе получилось бы два независимых движения,
        // которые рано или поздно разъезжаются.
        widget.onScrub(pos);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = (d.localPosition.dx / slot).floor().clamp(0, n - 1);
          if (i != widget.currentIndex) widget.onSelect(i);
        },
        onHorizontalDragStart: (d) {
          setState(() => _dragging = true);
          moveTo(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => moveTo(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onSelect(
              widget.position.value.round().clamp(0, n - 1));
        },
        child: SizedBox(
          height: 44,
          child: ValueListenableBuilder<double>(
            valueListenable: widget.position,
            builder: (context, pos, _) => Stack(
              children: [
                // Капсула следует за пальцем без задержки: любое сглаживание
                // здесь читается как «подтормаживает».
                Positioned(
                  left: slot * pos + (slot - pillW) / 2,
                  top: 2,
                  width: pillW,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        P.lime.withValues(alpha: _dragging ? 0.30 : 0.20),
                        P.violet.withValues(alpha: _dragging ? 0.26 : 0.18),
                      ]),
                      borderRadius: BorderRadius.circular(21),
                      boxShadow: widget.animate
                          ? [
                              BoxShadow(
                                  color: P.lime.withValues(
                                      alpha: _dragging ? 0.38 : 0.26),
                                  blurRadius: _dragging ? 22 : 16,
                                  spreadRadius: -3),
                            ]
                          : null,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        // Значок разгорается ПОСТЕПЕННО по мере наезда
                        // капсулы: видно, между какими вкладками палец.
                        child: _Tab(
                          icon: _icons[i],
                          t: (1 - (pos - i).abs()).clamp(0.0, 1.0),
                          animate: widget.animate,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;

  /// Насколько капсула наехала на эту вкладку: 0 — мимо, 1 — точно под ней.
  ///
  /// Дробное значение, а не «активна/нет»: при ведении пальцем вкладки должны
  /// разгораться постепенно, иначе подсветка едет плавно, а значки скачут.
  final double t;

  final bool animate;

  const _Tab({required this.icon, required this.t, this.animate = true});

  @override
  Widget build(BuildContext context) {
    // Нажатия у самой вкладки нет: и тап, и ведение слушает панель целиком —
    // иначе жест ведения обрывался бы на границе между вкладками.
    final color = Color.lerp(P.textFaint, P.limeText, t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Transform.scale(
          // Размер подсказывает выбор раньше цвета: глаз ловит изменение
          // величины быстрее, чем оттенка.
          scale: animate ? 1 + 0.15 * t : 1,
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}

class _TrafficBar extends StatefulWidget {
  final List<String> lines;
  final double upKbps;
  final double downKbps;
  const _TrafficBar(
      {required this.lines, required this.upKbps, required this.downKbps});

  @override
  State<_TrafficBar> createState() => _TrafficBarState();
}

class _TrafficBarState extends State<_TrafficBar> {
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    if (widget.lines.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        setState(() => _i = (_i + 1) % widget.lines.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(double kbps) {
    if (kbps >= 1024) {
      return '${(kbps / 1024).toStringAsFixed(1)} ${L.t('unit_mbps')}';
    }
    return '${kbps.toStringAsFixed(0)} ${L.t('unit_kbps')}';
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.lines.isEmpty
        ? L.t('traffic_via')
        : widget.lines[_i % widget.lines.length];
    return Container(
      color: P.surfaceLo,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.swap_vert, size: 15, color: P.limeText),
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                line,
                key: ValueKey(line),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: P.textDim, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_upward, size: 12, color: P.limeText),
            Text(_fmt(widget.upKbps),
                style: const TextStyle(
                    color: P.limeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 7),
            const Icon(Icons.arrow_downward, size: 12, color: P.limeText),
            Text(_fmt(widget.downKbps),
                style: const TextStyle(
                    color: P.limeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }
}
