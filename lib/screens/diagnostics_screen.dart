/// DPI-анализатор «Проверить блокировку». Когда VPN не подключается, помогает
/// понять причину: нет сети / сервер недоступен / провайдер режет протокол.
/// Все пробы идут в ОБХОД туннеля (прямое соединение), чтобы честно измерить.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

enum _St { pending, running, ok, warn, fail }

class _Step {
  final String title;
  _St state = _St.pending;
  String detail = '';
  _Step(this.title);
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final List<_Step> _steps = [
    _Step(L.t('diag_s_net')),
    _Step(L.t('diag_s_tcp')),
    _Step(L.t('diag_s_tls')),
    _Step(L.t('diag_s_tun')),
  ];
  bool _running = false;
  String _verdict = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<bool> _tcp(String host, int port, {Duration t = const Duration(seconds: 6)}) async {
    try {
      final s = await Socket.connect(host, port, timeout: t);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tls(String host, int port, {Duration t = const Duration(seconds: 8)}) async {
    try {
      final s = await SecureSocket.connect(host, port,
          timeout: t, onBadCertificate: (_) => true);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tunnel() async {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await c.getUrl(Uri.parse('https://www.gstatic.com/generate_204'));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      c.close(force: true);
      return resp.statusCode == 204 || resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _set(int i, _St s, String d) {
    if (!mounted) return;
    setState(() {
      _steps[i].state = s;
      _steps[i].detail = d;
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _verdict = '';
      for (final s in _steps) {
        s.state = _St.pending;
        s.detail = '';
      }
    });
    final state = context.read<AppState>();
    final srv = state.activeServer;

    // 1) интернет (прямая проба до публичного DNS)
    _set(0, _St.running, '');
    final net = await _tcp('1.1.1.1', 443);
    _set(0, net ? _St.ok : _St.fail, net ? L.t('diag_ok') : L.t('diag_nonet'));
    if (!net) {
      _finish(L.t('diag_v_nonet'));
      return;
    }

    if (srv == null) {
      _set(1, _St.warn, L.t('diag_no_srv2'));
      _finish(L.t('diag_v_nosrv'));
      return;
    }

    // 2) TCP до сервера в обход туннеля
    _set(1, _St.running, '${srv.address}:${srv.port}');
    final tcp = await _tcp(srv.address, srv.port);
    _set(1, tcp ? _St.ok : _St.fail,
        tcp ? L.t('diag_port_open') : L.t('diag_port_closed'));

    // 3) TLS-рукопожатие (Reality маскируется под TLS; сброс = DPI режет)
    _set(2, _St.running, '');
    final tls = await _tls(srv.address, srv.port);
    _set(2, tls ? _St.ok : _St.warn,
        tls ? L.t('diag_tls_ok') : L.t('diag_tls_dpi'));

    // 4) реальный трафик через туннель (если подключены)
    if (state.isConnected) {
      _set(3, _St.running, '');
      final tun = await _tunnel();
      _set(3, tun ? _St.ok : _St.fail,
          tun ? L.t('diag_tun_ok') : L.t('diag_tun_fail'));
    } else {
      _set(3, _St.warn, L.t('diag_tun_skip'));
    }

    // вердикт
    if (!tcp) {
      _finish(L.t('diag_v_tcp'));
    } else if (!tls) {
      _finish(L.t('diag_v_tls'));
    } else if (state.isConnected && _steps[3].state == _St.fail) {
      _finish(L.t('diag_v_tun'));
    } else {
      _finish(L.t('diag_v_ok'));
    }
  }

  void _finish(String v) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _verdict = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('diag_title'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            L.t('diag_intro'),
            style: const TextStyle(color: P.textDim, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final s in _steps) _row(s),
          const SizedBox(height: 18),
          if (_verdict.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: P.grad,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_verdict,
                  style: const TextStyle(
                      color: Color(0xFF0C1206),
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh),
            label: Text(_running ? L.t('diag_running') : L.t('diag_retry')),
          ),
        ],
      ),
    );
  }

  Widget _row(_Step s) {
    final (icon, color) = switch (s.state) {
      _St.pending => (Icons.circle_outlined, P.textFaint),
      _St.running => (Icons.autorenew, P.limeText),
      _St.ok => (Icons.check_circle, P.limeText),
      _St.warn => (Icons.error_outline, P.gold),
      _St.fail => (Icons.cancel, Color(0xFFE0574A)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: const TextStyle(color: P.text, fontSize: 14)),
                if (s.detail.isNotEmpty)
                  Text(s.detail,
                      style: const TextStyle(color: P.textFaint, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
