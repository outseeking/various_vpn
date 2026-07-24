/// Карточка статистики текущей сессии: время онлайн, скачано/отдано, текущая
/// скорость и мини-график скорости. Данные берёт из AppState (скорости пока
/// имитируются — структура готова под реальные из нативного ядра).
library;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme/app_palette.dart';

class SessionCard extends StatelessWidget {
  final Duration duration;
  final int bytesDown;
  final int bytesUp;
  final double speedDownKbps;
  final double speedUpKbps;
  final List<double> history; // принято (down)
  final List<double> historyUp; // отдано (up)

  const SessionCard({
    super.key,
    required this.duration,
    required this.bytesDown,
    required this.bytesUp,
    required this.speedDownKbps,
    required this.speedUpKbps,
    required this.history,
    this.historyUp = const [],
  });

  static String _dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  static String _bytes(int b) {
    if (b < 1024) return '$b ${L.t('unit_b')}';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} ${L.t('unit_kb')}';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} ${L.t('unit_mb')}';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ${L.t('unit_gb')}';
  }

  static String _speed(double kbps) {
    if (kbps < 1024) return '${kbps.toStringAsFixed(0)} ${L.t('unit_kbps')}';
    return '${(kbps / 1024).toStringAsFixed(1)} ${L.t('unit_mbps')}';
  }

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
        children: [
          Row(
            children: [
              _Metric(
                  icon: Icons.timer_outlined,
                  label: L.t('time'),
                  value: _dur(duration),
                  color: P.limeText),
              _div(),
              _Metric(
                  icon: Icons.south,
                  label: L.t('downloaded'),
                  value: _bytes(bytesDown),
                  color: P.limeText),
              _div(),
              _Metric(
                  icon: Icons.north,
                  label: L.t('uploaded'),
                  value: _bytes(bytesUp),
                  color: const Color(0xFFB48CE6)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparkPainter(history, historyUp),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: P.lime, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${L.t('received')} ↓ ${_speed(speedDownKbps)}',
                    style: const TextStyle(color: P.limeText, fontSize: 12)),
              ]),
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Color(0xFFB48CE6), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${L.t('sent')} ↑ ${_speed(speedUpKbps)}',
                    style: const TextStyle(color: Color(0xFFB48CE6), fontSize: 12)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _div() => Container(width: 0.5, height: 34, color: P.surfaceHi);
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Metric(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: P.text, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(label, style: const TextStyle(color: P.textFaint, fontSize: 10)),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> down;
  final List<double> up;
  _SparkPainter(this.down, this.up);

  Path _smooth(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _series(Canvas canvas, Size size, List<double> data, double maxV,
      Color color, {required bool fill}) {
    if (data.length < 2) return;
    final dx = size.width / (data.length - 1);
    final pts = <Offset>[
      for (var i = 0; i < data.length; i++)
        Offset(dx * i, size.height - (data[i] / maxV) * size.height * 0.86 - 2),
    ];
    final path = _smooth(pts);
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.30), const Color(0x00000000)],
            ).createShader(Offset.zero & size));
    }
    // мягкое свечение
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // основная линия
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color);
    // точка текущего значения
    canvas.drawCircle(pts.last, 3.0, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (down.length < 2) return;
    // Общий масштаб для обеих линий, чтобы они были сопоставимы.
    double mx = 1;
    for (final v in down) if (v > mx) mx = v;
    for (final v in up) if (v > mx) mx = v;
    _series(canvas, size, down, mx, P.lime, fill: true); // принято
    if (up.length >= 2) {
      _series(canvas, size, up, mx, const Color(0xFFB48CE6), fill: false); // отдано
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
