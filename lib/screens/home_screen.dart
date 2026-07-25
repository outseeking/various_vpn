/// Главный экран Various VPN — тёмная тема, глобус-карта, кнопка-переливание,
/// переключатель ИИ/Ручной, серверы по странам с флагами и кнопкой пинга.
library;

import 'dart:async';

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
import '../widgets/ambient_bars.dart';
import '../widgets/connect_button.dart';
import '../widgets/connect_glow.dart';
import '../widgets/flag.dart';
import '../widgets/tap_scale.dart';
import '../widgets/globe.dart';
import '../widgets/session_card.dart';
import 'import_screen.dart';
import 'qr_import_screen.dart';
import 'per_app_screen.dart';
import 'profile_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import '../widgets/streak_flame.dart';

/// Корневая оболочка приложения: 4 вкладки в PageView, между которыми можно
/// переключаться свайпом (Apps / Чат / Настройки) и тапом по нижней панели.
/// На вкладке-глобусе свайп страниц отключён — там горизонтальное движение
/// вращает сам глобус, поэтому уходим с неё только тапом по панели.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final PageController _pc = PageController();
  int _index = 0;

  void _go(int i) {
    if (i == _index) return;
    _pc.animateToPage(i,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pc.dispose();
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
        currentIndex: _index,
        onSelect: _go,
      ),
      body: PageView(
        controller: _pc,
        // На глобусе (0) свайп страниц выключен — жест отдан вращению глобуса.
        physics: _index == 0
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          HomeScreen(),
          PerAppScreen(inShell: true),
          SupportScreen(inShell: true),
          SettingsScreen(inShell: true),
        ],
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
  bool _globeTouch = false; // палец на глобусе → блокируем прокрутку списка

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
    // Всплывашку при подключении со сменой сервера/страны убрали по просьбе —
    // событие остаётся только в логах (state._log), экран не перекрывается.
    if (_state?.notice.value != null) _state!.notice.value = null;
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
              child: AmbientBars(connected: connected, animate: state.animationsOn)),
          if (state.animationsOn)
            Positioned.fill(child: ConnectGlow(connected: connected)),
          SafeArea(
        bottom: false,
        child: ListView(
          physics: _globeTouch
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 48),
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              behavior: HitTestBehavior.opaque,
              child: _Header(active: active, telegramOnly: state.telegramOnly),
            ),
            const SizedBox(height: 14),
            _ModeToggle(
              mode: state.mode,
              onChanged: state.setMode,
            ),
            const SizedBox(height: 10),

            // --- глобус ---
            // Пока палец на глобусе — отключаем прокрутку списка, иначе
            // вертикальный свайп «крадётся» ListView и глобус не вращается.
            Center(
              child: Listener(
                onPointerDown: (_) {
                  if (!_globeTouch) setState(() => _globeTouch = true);
                },
                onPointerUp: (_) {
                  if (_globeTouch) setState(() => _globeTouch = false);
                },
                onPointerCancel: (_) {
                  if (_globeTouch) setState(() => _globeTouch = false);
                },
                child: RepaintBoundary(
                  child: GlobeView(
                    size: 264,
                    markers: _markers(state),
                    focus: focus,
                    connected: connected,
                    packetFrom: connected ? Geo.origin : null,
                    animationsEnabled: state.animationsOn,
                  ),
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
                label: connecting
                    ? L.t('connecting')
                    : connected
                        ? L.t('protected')
                        : L.t('disconnected'),
                onTap: () {
                  if (connecting) return;
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
                (state.subActive ||
                    state.subUntil != null ||
                    state.hasServers)) ...[
              // Есть серверы (импорт по ссылке/ID) = доступ уже есть, даже если
              // бэкенд не вернул статус — считаем подписку активной, не пугаем
              // «подписки нет».
              _SubscriptionCard(
                active: state.subActive || state.hasServers,
                until: state.subUntil,
                serverCount: state.servers.length,
              ),
              const SizedBox(height: 10),
            ],

            // «Уже есть подписка?» — только когда доступа реально НЕТ (нет ни
            // активной подписки, ни импортированных серверов).
            if (!state.subActive && !state.hasServers) ...[
              const _SubActionsCard(),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 4),
            _ServersSection(state: state),
          ],
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
    final name = telegramOnly
        ? L.t('free_tg')
        : (active?.countryName ?? L.t('no_server'));
    final sub = telegramOnly
        ? L.t('free_tg_sub')
        : (active != null ? active!.transportLabel : L.t('import_hint'));
    final ping = active != null && active!.pingMs > 0 ? '${active!.pingMs} ms' : '—';

    return Row(
      children: [
        if (cc.isNotEmpty) CountryFlag(cc) else const Icon(Icons.public, size: 20, color: P.textFaint),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: P.text, fontSize: 15, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(color: P.textFaint, fontSize: 11)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(ping,
                style: const TextStyle(
                    color: P.limeText, fontSize: 15, fontWeight: FontWeight.w600)),
            Text(L.t('ping'), style: const TextStyle(color: P.textFaint, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

// ---------- переключатель режима ----------

class _ModeToggle extends StatelessWidget {
  final GlobalMode mode;
  final ValueChanged<GlobalMode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(GlobalMode m, String t) {
      final on = mode == m;
      return Expanded(
        child: TapScale(
          onTap: () => onChanged(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? P.lime : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(t,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? const Color(0xFF0C1206) : P.textFaint,
                )),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Свайп влево/вправо переключает режим (как сегменты в Telegram/iOS).
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -120 && mode != GlobalMode.manual) {
              onChanged(GlobalMode.manual);
            } else if (v > 120 && mode != GlobalMode.ai) {
              onChanged(GlobalMode.ai);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: P.surfaceLo,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: P.surfaceHi),
            ),
            child: Row(children: [
              seg(GlobalMode.ai, L.t('ai_auto')),
              seg(GlobalMode.manual, L.t('manual')),
            ]),
          ),
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              // Компактная сетка (2 в ряд) ↔ полный список (можно двигать).
              TapScale(
                onTap: () => state.setCompactServers(!state.compactServers),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: P.textFaint.withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                      state.compactServers
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_rounded,
                      size: 16,
                      color: P.textFaint),
                ),
              ),
              TapScale(
                onTap: state.busy
                    ? null
                    : () async {
                        await state.refreshSubscription();
                      },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: P.textFaint.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.refresh, size: 15, color: P.textFaint),
                    const SizedBox(width: 5),
                    Text(L.t('update_short'),
                        style: const TextStyle(color: P.textFaint, fontSize: 12)),
                  ]),
                ),
              ),
              TapScale(
                onTap: state.busy ? null : state.pingAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: P.lime.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    state.busy
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: P.limeText))
                        : const Icon(Icons.radar, size: 14, color: P.limeText),
                    const SizedBox(width: 5),
                    Text(L.t('ping_btn'),
                        style: const TextStyle(color: P.limeText, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
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
                          checkColor: const Color(0xFF0C1206),
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
              leading: const Icon(Icons.layers_clear_outlined, color: P.textFaint),
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
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE2504A)),
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
          active: state.activeServer?.id == s.id,
          onTap: () {
            state.setManualServer(s.id);
            if (state.mode != GlobalMode.manual) {
              state.setMode(GlobalMode.manual);
            }
          },
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
                  onDragStarted: () => HapticFeedback.mediumImpact(),
                  // Тащим «поднятую» карточку с тенью — понятно, что схватили.
                  feedback: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      width: w,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 18,
                                spreadRadius: 1),
                          ],
                        ),
                        child: cellFor(s),
                      ),
                    ),
                  ),
                  childWhenDragging:
                      Opacity(opacity: 0.25, child: cellFor(s)),
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
class _FullList extends StatelessWidget {
  final AppState state;
  const _FullList({required this.state});

  @override
  Widget build(BuildContext context) {
    final list = state.visibleServers;
    Widget rowFor(VpnServer s) => _ServerRow(
          key: ValueKey(s.id),
          server: s,
          active: state.activeServer?.id == s.id,
          onTap: () {
            state.setManualServer(s.id);
            if (state.mode != GlobalMode.manual) {
              state.setMode(GlobalMode.manual);
            }
          },
          onRename: () => _ServersSection._showRenameDialog(context, state, s),
          onDelete: () => _ServersSection._confirmDelete(context, state, s),
          onFolder: () => _ServersSection._showFolderPicker(context, state, s),
        );

    if (state.activeFolder.isNotEmpty) {
      // Внутри папки порядок общий — просто список без перетаскивания.
      return Column(children: [for (final s in list) rowFor(s)]);
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: state.reorderServers,
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
                  color: active ? P.lime : P.surfaceHi, width: active ? 1 : 0.5),
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
        title: Text(L.t('folder_delete_q'), style: const TextStyle(color: P.text)),
        content: Text(name, style: const TextStyle(color: P.textDim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE2504A)),
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
                      ? '${L.t('free_auto_sub')} · ${server!.countryName}'
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
  final bool locked; // бесплатный режим: сервер недоступен (тусклый, по тапу — апселл)
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
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: P.pingColor(server.pingMs,
                      proxy: context.read<AppState>().pingType == 'proxy')),
            ),
            Text(
              server.pingMs > 0 ? '${server.pingMs} ms' : '—',
              style: TextStyle(
                  color: active ? P.limeText : P.textFaint, fontSize: 12),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle, color: P.lime, size: 18),
            ],
            if (locked) ...[
              const SizedBox(width: 6),
              const Icon(Icons.lock_outline, color: P.textFaint, size: 15),
            ],
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
                      const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFE2504A)),
                      const SizedBox(width: 10),
                      Text(L.t('delete'),
                          style: const TextStyle(color: Color(0xFFE2504A))),
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

/// Компактная ячейка сервера (2 в ряд): флаг + страна + пинг + ⋮.
class _CompactServerCell extends StatelessWidget {
  final VpnServer server;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onFolder;
  const _CompactServerCell({
    required this.server,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onFolder,
  });

  @override
  Widget build(BuildContext context) {
    // 2 ячейки в ряд: (ширина контента − отступ) / 2. Отступы ListView = 18.
    final w = (MediaQuery.of(context).size.width - 18 * 2 - 8) / 2;
    final proxy = context.read<AppState>().pingType == 'proxy';
    return SizedBox(
      width: w,
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
                  Row(children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: P.pingColor(server.pingMs, proxy: proxy)),
                    ),
                    Text(server.pingMs > 0 ? '${server.pingMs} ms' : '—',
                        style: TextStyle(
                            color: active ? P.limeText : P.textFaint,
                            fontSize: 11)),
                  ]),
                ],
              ),
            ),
            SizedBox(
              width: 26,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: P.textFaint, size: 18),
                color: P.surface,
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'folder') onFolder();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        const Icon(Icons.edit_outlined, size: 18, color: P.text),
                        const SizedBox(width: 10),
                        Text(L.t('srv_rename'),
                            style: const TextStyle(color: P.text)),
                      ])),
                  PopupMenuItem(
                      value: 'folder',
                      child: Row(children: [
                        const Icon(Icons.folder_outlined, size: 18, color: P.text),
                        const SizedBox(width: 10),
                        Text(L.t('srv_move_folder'),
                            style: const TextStyle(color: P.text)),
                      ])),
                  PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline,
                            size: 18, color: Color(0xFFE2504A)),
                        const SizedBox(width: 10),
                        Text(L.t('delete'),
                            style: const TextStyle(color: Color(0xFFE2504A))),
                      ])),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- карточка бесплатного (пробного) доступа · только Telegram ----------

/// Меню активации полного доступа — единая точка «как купить/подключить».
/// Открывается по кнопке в карточке бесплатного режима и из быстрых действий.
void showActivateSheet(BuildContext context) {
  Future<void> pasteImport() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (txt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.t('act_paste_empty'))));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(L.t('act_paste_ok'))));
    final ok = await context.read<AppState>().importSmart(txt);
    if (context.mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<AppState>().lastError ?? 'Ошибка')));
    }
  }

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
                  color: primary
                      ? const Color(0x260C1206)
                      : P.lime.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: primary ? const Color(0xFF0C1206) : P.limeText,
                    size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: primary ? const Color(0xFF0C1206) : P.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            color: primary
                                ? const Color(0xCC0C1206)
                                : P.textFaint,
                            fontSize: 12,
                            height: 1.3)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: primary ? const Color(0xFF0C1206) : P.textFaint),
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
                const Icon(Icons.workspace_premium, color: P.limeText, size: 22),
                const SizedBox(width: 8),
                Text(L.t('act_title'),
                    style: const TextStyle(
                        color: P.text, fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(L.t('act_sub'),
                    style: const TextStyle(color: P.textFaint, fontSize: 12.5)),
              ),
              const SizedBox(height: 14),
              row(Icons.workspace_premium, L.t('act_get_bot'),
                  L.t('act_get_bot_d'),
                  () => launchUrl(Uri.parse(Brand.bot),
                      mode: LaunchMode.externalApplication),
                  primary: true),
              row(Icons.telegram, L.t('act_link_tg'), L.t('act_link_tg_d'),
                  () => showLinkTelegramDialog(context)),
              row(Icons.link, L.t('act_link'), L.t('act_link_d'),
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ImportScreen()))),
              row(Icons.qr_code_scanner, L.t('act_qr'), L.t('act_qr_d'),
                  () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const QrImportScreen()))),
              row(Icons.content_paste_rounded, L.t('act_paste'),
                  L.t('act_paste_d'), pasteImport),
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
    final srvName = server?.countryName ?? '—';
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
            const Expanded(
              child: _SubMetric(
                icon: Icons.all_inclusive,
                label: 'Трафик / Traffic',
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
                      color: Color(0xFF0C1206), size: 18),
                  const SizedBox(width: 8),
                  Text(L.t('free_buy_full'),
                      style: const TextStyle(
                          color: Color(0xFF0C1206),
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

  static const _monthsRu = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];
  static const _monthsEn = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  String _fmtDate(DateTime d) {
    final m = L.current == 'en' ? _monthsEn[d.month] : _monthsRu[d.month];
    return L.current == 'en' ? '$m ${d.day}, ${d.year}' : '${d.day} $m ${d.year}';
  }

  int? get _daysLeft => until?.difference(DateTime.now()).inDays;

  @override
  Widget build(BuildContext context) {
    final days = _daysLeft;
    final ok = active && (days == null || days >= 0);
    final accent = ok ? P.lime : const Color(0xFFE2504A);
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
                  value: until != null ? _fmtDate(until!) : '—',
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
          Text(label, style: const TextStyle(color: P.textFaint, fontSize: 11)),
        ]),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: P.text, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Быстрые действия с подпиской на главном экране (вставить ссылку / привязать TG).
class _SubActionsCard extends StatelessWidget {
  const _SubActionsCard();

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, VoidCallback onTap,
        {bool primary = false}) {
      return Expanded(
        child: TapScale(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: primary ? P.grad : null,
              color: primary ? null : P.surfaceLo,
              borderRadius: BorderRadius.circular(12),
              border: primary ? null : Border.all(color: P.surfaceHi),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 20,
                    color: primary ? const Color(0xFF0C1206) : P.limeText),
                const SizedBox(height: 5),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: primary ? const Color(0xFF0C1206) : P.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

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
          Row(children: [
            btn(Icons.link, L.t('sub_actions_import'), () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen()),
              );
            }),
            const SizedBox(width: 10),
            btn(Icons.telegram, L.t('sub_actions_link_tg'),
                () => showLinkTelegramDialog(context),
                primary: true),
          ]),
        ],
      ),
    );
  }
}

// ---------- нижняя панель: трафик + табы ----------

class _BottomBar extends StatelessWidget {
  final List<String> trafficLines;
  final bool showTraffic;
  final double upKbps;
  final double downKbps;
  final bool animate;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const _BottomBar({
    required this.trafficLines,
    required this.showTraffic,
    required this.upKbps,
    required this.downKbps,
    required this.currentIndex,
    required this.onSelect,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final navInner = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: _navRow(context),
      ),
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
        if (showTraffic)
          _TrafficBar(lines: trafficLines, upKbps: upKbps, downKbps: downKbps),
        nav,
      ],
    );
  }

  static const _icons = [
    Icons.public,
    Icons.apps,
    Icons.chat_bubble_outline,
    Icons.settings_outlined,
  ];

  Widget _navRow(BuildContext context) {
    const n = 4;
    return LayoutBuilder(builder: (context, c) {
      final slot = c.maxWidth / n;
      final pillW = slot * 0.66;
      return SizedBox(
        height: 48,
        child: Stack(
          children: [
            // Плавно «переезжающий» индикатор под активной вкладкой (мягкая
            // лаймово-фиолетовая капсула со свечением). В Lite — без свечения.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              left: slot * currentIndex + (slot - pillW) / 2,
              top: 3,
              width: pillW,
              height: 42,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    P.lime.withValues(alpha: 0.20),
                    P.violet.withValues(alpha: 0.18),
                  ]),
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: animate
                      ? [
                          BoxShadow(
                              color: P.lime.withValues(alpha: 0.26),
                              blurRadius: 16,
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
                    child: _Tab(
                      icon: _icons[i],
                      active: currentIndex == i,
                      animate: animate,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool animate;
  final VoidCallback? onTap;
  const _Tab(
      {required this.icon,
      this.active = false,
      this.animate = true,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    // Иконка плавно меняет цвет (активная — лайм). Индикатор-капсула едет
    // отдельно (в _navRow), поэтому у самой вкладки фона нет.
    final glyph = TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 280),
      tween: ColorTween(end: active ? P.limeText : P.textFaint),
      builder: (_, color, __) => Icon(icon, color: color, size: 24),
    );
    if (!animate) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Icon(icon, color: active ? P.limeText : P.textFaint, size: 24),
          ),
        ),
      );
    }
    // Активная иконка чуть подрастает (пружиной) — вместе с едущей капсулой.
    return TapScale(
      onTap: onTap,
      scale: 0.85,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 1, end: active ? 1.15 : 1.0),
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: glyph,
          ),
        ),
      ),
    );
  }
}

// Строка над табами: что → куда идёт (страна/маршрут) + текущая скорость.
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
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} ${L.t('unit_mbps')}';
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
                    color: P.limeText, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 7),
            const Icon(Icons.arrow_downward, size: 12, color: P.limeText),
            Text(_fmt(widget.downKbps),
                style: const TextStyle(
                    color: P.limeText, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ],
      ),
    );
  }
}
