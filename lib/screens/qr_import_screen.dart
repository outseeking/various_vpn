/// Импорт подписки по QR-коду: наводим камеру на QR из бота Various VPN.
/// Считанная ссылка проходит ту же проверку «наша подписка», что и обычный импорт.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/app_toast.dart';

class QrImportScreen extends StatefulWidget {
  const QrImportScreen({super.key});

  @override
  State<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends State<QrImportScreen>
    with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController();
  bool _handled = false;
  late final AnimationController _scan = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat(reverse: true);

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_handled) return;
    final raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
    if (raw == null || raw.trim().isEmpty) return;
    _handled = true;
    // Состояние берём ДО остановки камеры: после await использовать context
    // нельзя — экран мог уже закрыться, и обращение к нему упадёт.
    final state = context.read<AppState>();
    await _controller.stop();
    final ok = await state.importSmart(raw.trim());
    if (!mounted) return;
    if (ok) {
      AppToast.ok(context, '${L.t('qr_added')}: ${state.servers.length}');
    } else {
      AppToast.error(context, state.lastError ?? L.t('qr_fail'));
    }
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _handled = false;
      await _controller.start();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
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
          // Затемняем всё, кроме окна визира: глаз сам находит, куда наводить.
          const _ScanMask(),
          // Уголки вместо сплошной рамки + бегущая линия: видно, что камера
          // действительно ищет код, а не просто застыла.
          SizedBox(
            width: 244,
            height: 244,
            child: AnimatedBuilder(
              animation: _scan,
              builder: (_, __) => CustomPaint(painter: _ScanFrame(_scan.value)),
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
                style: const TextStyle(color: P.text, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Затемнение вокруг окна визира.
class _ScanMask extends StatelessWidget {
  const _ScanMask();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _MaskPainter()),
      );
}

class _MaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const side = 244.0;
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: size.center(Offset.zero), width: side, height: side),
      const Radius.circular(24),
    );
    final full = Path()..addRect(Offset.zero & size);
    final cut = Path()..addRRect(hole);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cut),
      Paint()..color = const Color(0xB3000000),
    );
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) => false;
}

/// Уголки визира + бегущая линия сканирования.
class _ScanFrame extends CustomPainter {
  final double t; // 0..1, туда-обратно
  _ScanFrame(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const len = 34.0; // длина уголка
    const r = 24.0; // радиус скругления
    final p = Paint()
      ..color = P.lime
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void corner(double x, double y, double sx, double sy) {
      final path = Path()
        ..moveTo(x + sx * (r + len), y)
        ..lineTo(x + sx * r, y)
        ..arcToPoint(Offset(x, y + sy * r),
            radius: const Radius.circular(r), clockwise: sx * sy < 0)
        ..lineTo(x, y + sy * (r + len));
      canvas.drawPath(path, p);
    }

    corner(0, 0, 1, 1);
    corner(w, 0, -1, 1);
    corner(0, h, 1, -1);
    corner(w, h, -1, -1);

    // Линия сканирования: плавно ходит сверху вниз, к краям притухая.
    final y = 14 + (h - 28) * Curves.easeInOut.transform(t);
    final fade = math.sin(t * math.pi).clamp(0.25, 1.0);
    canvas.drawLine(
      Offset(16, y),
      Offset(w - 16, y),
      Paint()
        ..shader = LinearGradient(colors: [
          P.lime.withValues(alpha: 0),
          P.lime.withValues(alpha: 0.85 * fade),
          P.lime.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(16, y - 1, w - 32, 2))
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFrame old) => old.t != t;
}
