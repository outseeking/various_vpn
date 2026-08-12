/// Витрина элементов в стиле iOS — чтобы оценить их руками, а не по описанию.
///
/// Экран нужен ровно для одного: пощупать. Анимацию и отклик нельзя проверить
/// по скриншоту — тумблер либо ощущается живым, либо нет, и понять это можно
/// только пальцем. Здесь всё собрано в одном месте и работает по-настоящему.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import '../theme/motion.dart';
import '../widgets/glass.dart';
import '../widgets/ios_segmented.dart';
import '../widgets/ios_switch.dart';
import '../widgets/ios_tab_bar.dart';
import '../widgets/tap_scale.dart';

class IosPreviewScreen extends StatefulWidget {
  const IosPreviewScreen({super.key});

  @override
  State<IosPreviewScreen> createState() => _IosPreviewScreenState();
}

class _IosPreviewScreenState extends State<IosPreviewScreen> {
  bool _a = true;
  bool _b = false;
  bool _c = true;
  String _mode = 'auto';
  bool _sheetOpen = false;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: const Text('Стиль iOS')),
      body: Stack(children: [
        // Живой фон: без него стекло не показать — размывать было бы нечего.
        const Positioned.fill(child: _Aurora()),
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            const _Caption('Тумблеры',
                'Потяни пальцем, а не только нажми. Бегунок вытягивается '
                    'под пальцем и доезжает с лёгким перелётом.'),
            GlassPanel(
              child: Column(children: [
                _Row('Раздельный туннель', _a, (v) => setState(() => _a = v)),
                const _Line(),
                _Row('Блокировка рекламы', _b, (v) => setState(() => _b = v)),
                const _Line(),
                _Row('Автоподключение', _c, (v) => setState(() => _c = v)),
              ]),
            ),
            const SizedBox(height: 26),

            const _Caption('Сегменты',
                'ВЕДИ пальцем, не отрывая: таблетка следует за ним, подписи '
                    'разгораются по мере наезда. Тап тоже работает.'),
            GlassPanel(
              child: IosSegmented<String>(
                value: _mode,
                items: const [
                  ('auto', 'Авто'),
                  ('manual', 'Ручной'),
                  ('off', 'Выкл'),
                ],
                onChanged: (v) => setState(() => _mode = v),
              ),
            ),
            const SizedBox(height: 26),

            const _Caption('Нижние вкладки',
                'То же перетаскивание: проведи вдоль панели — подсветка едет '
                    'за пальцем, значки разгораются постепенно.'),
            IosTabBar(
              items: const [
                IosTabItem(Icons.public, 'Главная'),
                IosTabItem(Icons.apps, 'Приложения'),
                IosTabItem(Icons.chat_bubble_outline, 'Поддержка'),
                IosTabItem(Icons.settings, 'Настройки'),
              ],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 26),

            const _Caption('Стекло',
                'Слой размывает то, что под ним, кромка ловит свет сверху и '
                    'гаснет книзу. Подвигай экран — фон живой.'),
            const Row(children: [
              Expanded(
                child: GlassPanel(
                  padding: EdgeInsets.all(18),
                  child: Column(children: [
                    Icon(Icons.bolt, color: P.limeText, size: 26),
                    SizedBox(height: 8),
                    Text('85 ms',
                        style: TextStyle(
                            color: P.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    Text('Германия',
                        style: TextStyle(color: P.textFaint, fontSize: 12.5)),
                  ]),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: GlassPanel(
                  padding: EdgeInsets.all(18),
                  opacity: 0.35,
                  child: Column(children: [
                    Icon(Icons.shield_outlined,
                        color: P.violetSoft, size: 26),
                    SizedBox(height: 8),
                    Text('Тоньше',
                        style: TextStyle(
                            color: P.text,
                            fontSize: 19,
                            fontWeight: FontWeight.w800)),
                    Text('плёнка',
                        style: TextStyle(color: P.textFaint, fontSize: 12.5)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 26),

            const _Caption('Шторка',
                'Выезжает снизу с оттяжкой и уходит быстрее, чем приходит — '
                    'так делает система.'),
            TapScale(
              haptic: true,
              onTap: () => setState(() => _sheetOpen = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: P.grad,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('Открыть шторку',
                      style: TextStyle(
                          color: P.onLime,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
        if (_sheetOpen)
          _Sheet(onClose: () => setState(() => _sheetOpen = false)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Row(this.title, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  color: P.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
        ),
        IosSwitch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line();
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: P.surfaceHi);
}

class _Caption extends StatelessWidget {
  final String title;
  final String body;
  const _Caption(this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: P.text, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(body,
            style: const TextStyle(
                color: P.textFaint, fontSize: 12.5, height: 1.4)),
      ]),
    );
  }
}

/// Шторка с той же повадкой, что у системной: приходит мягко, уходит быстрее.
class _Sheet extends StatefulWidget {
  final VoidCallback onClose;
  const _Sheet({required this.onClose});

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: M.page,
    reverseDuration: M.pageOut,
  )..forward();

  Future<void> _close() async {
    await _c.reverse();
    widget.onClose();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: Container(color: Colors.black.withValues(alpha: 0.5 * t)),
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10 - 320 * (1 - t),
            child: GlassPanel(
              opacity: 0.8,
              radius: 28,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: P.surfaceHi,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Стекло и движение',
                    style: TextStyle(
                        color: P.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Фон под шторкой размыт, кромка ловит свет сверху. '
                  'Закрыть можно нажатием по затемнению.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: P.textDim, fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 18),
                TapScale(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _close();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: P.grad,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('Понятно',
                          style: TextStyle(
                              color: P.onLime,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

/// Медленно плывущие цветные пятна. Нужны, чтобы стеклу было что размывать:
/// на ровном фоне размытие не видно вовсе.
class _Aurora extends StatefulWidget {
  const _Aurora();

  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _AuroraPainter(_c.value),
        size: Size.infinite,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = P.bg);
    void blob(double phase, Color color, double r) {
      final a = (t + phase) * 6.28318;
      final c = Offset(
        size.width * (0.5 + 0.36 * (0.6 * (a).remainder(6.28318) / 3.14 - 1)),
        size.height * (0.30 + 0.22 * (phase * 2 - 1)),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    blob(0.0, P.lime, size.width * 0.55);
    blob(0.5, P.violet, size.width * 0.6);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}
