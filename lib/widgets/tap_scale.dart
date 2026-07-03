/// Обёртка для тактильной анимации нажатия: при касании дочерний виджет слегка
/// «вжимается» (scale вниз) и плавно возвращается. Делает тапы по кастомным
/// кнопкам/строкам понятными — есть визуальный отклик.
library;

import 'package:flutter/material.dart';

class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale; // насколько сжимать (0.96 = лёгкое нажатие)
  final HitTestBehavior behavior;

  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
