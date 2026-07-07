/// Главный экран Various VPN — тёмная тема, глобус-карта, кнопка-переливание,
/// переключатель ИИ/Ручной, серверы по странам с флагами и кнопкой пинга.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'per_app_screen.dart';
import 'profile_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import '../widgets/streak_flame.dart';

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
    // В двойном VPN «выбранная» точка глобуса = выход (конечная страна пути).
    final target = s.multihopExit ?? s.activeServer;
    final seen = <String>{};
    final out = <GlobeMarker>[];
    for (final srv in s.servers) {
      final cc = srv.countryCode;
      final ll = Geo.of(cc);
      if (ll == null || !seen.add(cc)) continue;
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
    // В двойном VPN глобус смотрит на выход, а вход подсвечивается как relay.
    final exit = state.multihopExit;
    final target = exit ?? active;
    final focus = target != null ? Geo.of(target.countryCode) : null;
    final relayLoc = (exit != null && active != null)
        ? Geo.of(active.countryCode)
        : null;

    return Scaffold(
      backgroundColor: P.bg,
      bottomNavigationBar: _BottomBar(
        trafficLines: connected ? state.trafficLines : const [],
        showTraffic: connected,
        upKbps: state.speedUpKbps,
        downKbps: state.speedDownKbps,
      ),
      body: Stack(
        children: [
          Positioned.fill(
              child: AmbientBars(connected: connected, animate: state.animationsOn)),
          Positioned.fill(child: ConnectGlow(connected: connected)),
          SafeArea(
        bottom: false,
        child: ListView(
          physics: _globeTouch
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
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
                    relay: connected ? relayLoc : null,
                    relayLabel: (connected && exit != null && active != null)
                        ? active.countryName
                        : null,
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
                busy: connecting || state.busy,
                label: connecting
                    ? L.t('connecting')
                    : connected
                        ? L.t('protected')
                        : L.t('disconnected'),
                onTap: () {
                  if (connecting) return;
                  connected ? state.disconnect() : state.connect();
                },
              ),
            ),
            const SizedBox(height: 6),

            if (connected) ...[
              SessionCard(
                duration: state.sessionDuration,
                bytesDown: state.bytesDown,
                bytesUp: state.bytesUp,
                speedDownKbps: state.speedDownKbps,
                speedUpKbps: state.speedUpKbps,
                history: state.speedHistory,
              ),
              const SizedBox(height: 14),
            ],

            if (state.subLoaded && (state.subActive || state.subUntil != null)) ...[
              _SubscriptionCard(
                active: state.subActive,
                until: state.subUntil,
                serverCount: state.servers.length,
              ),
              const SizedBox(height: 10),
            ],

            if (!state.hasServers && !state.telegramOnly)
              _ImportCard(),

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
        Container(
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
              TapScale(
                onTap: state.busy
                    ? null
                    : () async {
                        await state.refreshSubscription();
                      },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: P.textFaint.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.refresh, size: 16, color: P.textFaint),
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
        // Перетаскиваемый список: пользователь сам задаёт порядок серверов
        // (удерживай и тащи). Порядок сохраняется.
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: true,
          onReorder: state.reorderServers,
          children: [
            for (final s in state.servers)
              _ServerRow(
                key: ValueKey(s.id),
                server: s,
                active: state.activeServer?.id == s.id,
                onTap: () {
                  state.setManualServer(s.id);
                  if (state.mode != GlobalMode.manual) {
                    state.setMode(GlobalMode.manual);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  final VpnServer server;
  final bool active;
  final VoidCallback onTap;
  const _ServerRow(
      {super.key,
      required this.server,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
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
                  shape: BoxShape.circle, color: P.pingColor(server.pingMs)),
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
          ],
        ),
      ),
    );
  }
}

// ---------- карточка подписки (как в Quattro) ----------

class _SubscriptionCard extends StatelessWidget {
  final bool active;
  final DateTime? until;
  final int serverCount;
  const _SubscriptionCard({
    required this.active,
    required this.until,
    required this.serverCount,
  });

  static const _months = [
    '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];

  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month]} ${d.year}';

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
              Text(ok ? 'Подписка активна' : 'Подписка неактивна',
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
                  child: Text('$days дн.',
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
                  label: 'Действует до',
                  value: until != null ? _fmtDate(until!) : '—',
                ),
              ),
              Container(width: 0.5, height: 30, color: P.surfaceHi),
              Expanded(
                child: _SubMetric(
                  icon: Icons.dns_outlined,
                  label: 'Серверов',
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

class _ImportCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.surfaceHi),
      ),
      child: ListTile(
        leading: const Icon(Icons.link, color: P.limeText),
        title: Text(L.t('no_servers'), style: const TextStyle(color: P.text)),
        subtitle: Text(L.t('no_servers_sub'),
            style: const TextStyle(color: P.textFaint)),
        trailing: const Icon(Icons.chevron_right, color: P.textFaint),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ImportScreen()),
        ),
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
  const _BottomBar({
    required this.trafficLines,
    required this.showTraffic,
    required this.upKbps,
    required this.downKbps,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTraffic)
          _TrafficBar(lines: trafficLines, upKbps: upKbps, downKbps: downKbps),
        Container(
          decoration: const BoxDecoration(
            color: P.surface,
            border: Border(top: BorderSide(color: P.surfaceHi)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  const _Tab(icon: Icons.public, active: true),
              _Tab(
                icon: Icons.apps,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PerAppScreen()),
                ),
              ),
              _Tab(
                icon: Icons.chat_bubble_outline,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
              ),
                  _Tab(
                    icon: Icons.settings_outlined,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  const _Tab({required this.icon, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: active ? P.limeText : P.textFaint, size: 24),
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
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} МБ/с';
    return '${kbps.toStringAsFixed(0)} КБ/с';
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
