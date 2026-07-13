/// Импорт подписки по QR-коду: наводим камеру на QR из бота Various VPN.
/// Считанная ссылка проходит ту же проверку «наша подписка», что и обычный импорт.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';

class QrImportScreen extends StatefulWidget {
  const QrImportScreen({super.key});

  @override
  State<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends State<QrImportScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_handled) return;
    final raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (raw == null || raw.trim().isEmpty) return;
    _handled = true;
    await _controller.stop();
    final state = context.read<AppState>();
    final ok = await state.importSmart(raw.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: P.surface,
      content: Text(ok
          ? '${L.t('qr_added')}: ${state.servers.length}'
          : (state.lastError ?? L.t('qr_fail'))),
    ));
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _handled = false;
      await _controller.start();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('qr_title'))),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // рамка-визир в стиле приложения
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: P.limeText, width: 2.5),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                L.t('qr_hint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: P.text, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
