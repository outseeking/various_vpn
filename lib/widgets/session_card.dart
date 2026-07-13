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
  final List<double> history;

  const SessionCard({
    super.key,
    required this.duration,
    required this.bytesDown,
    required this.bytesUp,
    required this.speedDownKbps,
    required this.speedUpKbps,
    required this.history,
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
            height: 38,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparkPainter(history),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('↓ ${_speed(speedDownKbps)}',
                  style: const TextStyle(color: P.limeText, fontSize: 12)),
              Text('↑ ${_speed(speedUpKbps)}',
                  style: const TextStyle(color: Color(0xFFB48CE6), fontSize: 12)),
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
  final List<double> data;
  _SparkPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxV = data.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    final dx = size.width / (data.length - 1);
    // точки
    final pts = <Offset>[
      for (var i = 0; i < data.length; i++)
        Offset(dx * i, size.height - (data[i] / maxV) * size.height * 0.9 - 2),
    ];
    // сглаживание Catmull-Rom → кубические Безье (плавная линия без ступенек)
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
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x557CB10F), Color(0x00000000)],
          ).createShader(Offset.zero & size));

    // мягкое свечение под линией
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = P.lime.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // основная линия с градиентом лайм→фиолет
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = const LinearGradient(
            colors: [P.violet, P.lime],
          ).createShader(Offset.zero & size));

    // точка текущего значения
    final last = pts.last;
    canvas.drawCircle(last, 3.2, Paint()..color = P.lime);
    canvas.drawCircle(
        last,
        5.5,
        Paint()
          ..color = P.lime.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}
