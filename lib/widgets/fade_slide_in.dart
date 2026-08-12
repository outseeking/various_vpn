/// Появление элемента списка: лёгкий подъём + проявление, с задержкой по
/// порядковому номеру.
///
/// Список, который возникает целиком и сразу, читается как «перерисовали
/// экран». Каскад в 40 мс на элемент даёт ощущение, что содержимое
/// выкладывается — это то самое «дорого», ради которого всё и делается.
/// Каскад ограничен первыми элементами: ждать полсекунды ради двадцатой
/// строки никто не станет.
library;

import 'package:flutter/material.dart';

import '../theme/motion.dart';

class FadeSlideIn extends StatefulWidget {
  final Widget child;

  /// Порядковый номер в списке — задаёт задержку старта.
  final int index;

  /// Максимальное число элементов, участвующих в каскаде.
  final int maxStaggered;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.maxStaggered = 8,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: M.slow);

  @override
  void initState() {
    super.initState();
    final steps = widget.index.clamp(0, widget.maxStaggered);
    Future<void>.delayed(M.stagger * steps, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: M.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}
