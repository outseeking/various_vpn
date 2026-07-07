/// Тест скорости со спидометром. Реальный замер: потоковая загрузка с
/// Cloudflare speed-эндпоинта, живая стрелка и итоговая скорость (Мбит/с).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import '../theme/app_palette.dart';

class SpeedtestScreen extends StatefulWidget {
  const SpeedtestScreen({super.key});

  @override
  State<SpeedtestScreen> createState() => _SpeedtestScreenState();
}

class _SpeedtestScreenState extends State<SpeedtestScreen> {
  double _mbps = 0; // текущая стрелка
  double _result = 0; // итог
  bool _running = false;
  String _status = 'Готов к тесту';

  static const _maxMbps = 200.0; // верх шкалы
  static const _url =
      'https://speed.cloudflare.com/__down?bytes=20000000'; // 20 МБ

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _mbps = 0;
      _result = 0;
      _status = 'Измеряем загрузку…';
    });
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(_url));
      final resp = await client.send(req);
      var bytes = 0;
      final sw = Stopwatch()..start();
      var lastBytes = 0;
      var lastMs = 0;
      await for (final chunk in resp.stream) {
        bytes += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (ms - lastMs >= 200) {
          final inst = (bytes - lastBytes) * 8 / 1000 / (ms - lastMs); // Мбит/с
          lastBytes = bytes;
          lastMs = ms;
          if (mounted) setState(() => _mbps = inst.clamp(0, _maxMbps).toDouble());
        }
      }
      sw.stop();
      client.close();
      final avg = bytes * 8 / 1000 / sw.elapsedMilliseconds; // Мбит/с
      if (mounted) {
        setState(() {
          _result = avg;
          _mbps = avg.clamp(0, _maxMbps).toDouble();
          _status = 'Готово';
          _running = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Ошибка теста (проверь соединение)';
          _running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: const Text('Тест скорости')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            SizedBox(
              width: 280,
              height: 200,
              child: CustomPaint(
                painter: _GaugePainter(_mbps / _maxMbps),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 36),
                      Text(_mbps.toStringAsFixed(1),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: P.text, fontSize: 40)),
                      const Text('Мбит/с',
                          style: TextStyle(color: P.textFaint, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(_status, style: const TextStyle(color: P.textDim, fontSize: 14)),
            if (_result > 0) ...[
              const SizedBox(height: 8),
              Text('Средняя: ${_result.toStringAsFixed(1)} Мбит/с',
                  style: const TextStyle(color: P.limeText, fontSize: 14)),
              const SizedBox(height: 10),
              Builder(builder: (_) {
                // Вердикт по скорости: >30 отлично, 8–30 нормально, <8 медленно.
                final (label, color, icon) = _result >= 30
                    ? (L.t('net_good'), P.limeText, Icons.check_circle)
                    : _result >= 8
                        ? (L.t('net_ok'), P.gold, Icons.thumb_up_alt_outlined)
                        : (L.t('net_slow'), const Color(0xFFE0574A),
                            Icons.warning_amber_rounded);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                );
              }),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(22),
              child: GestureDetector(
                onTap: _running ? null : _run,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: _running ? null : P.grad,
                    color: _running ? P.surfaceLo : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_running ? 'Идёт тест…' : 'Начать тест',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _running ? P.textFaint : const Color(0xFF0C1206),
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double t; // 0..1
  _GaugePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 10);
    final r = size.width / 2 - 12;
    const start = math.pi * 0.8;
    const sweep = math.pi * 1.4;

    // фон-дуга
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..color = P.surfaceHi);

    // заполненная дуга (градиент)
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep * t.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            colors: [P.lime, P.violet],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // стрелка
    final ang = start + sweep * t.clamp(0, 1);
    final tip = Offset(c.dx + r * 0.8 * math.cos(ang), c.dy + r * 0.8 * math.sin(ang));
    canvas.drawLine(
        c,
        tip,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = P.limeText);
    canvas.drawCircle(c, 6, Paint()..color = P.lime);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.t != t;
}
