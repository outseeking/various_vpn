/// Сплеш-экран при запуске: анимация логотипа, затем переход на нужный экран.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme/app_palette.dart';
import '../widgets/brand_logo.dart';

class SplashScreen extends StatefulWidget {
  /// Куда уйти после сплеша.
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..forward();

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, a, __) =>
            FadeTransition(opacity: a, child: widget.next),
      ));
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AnimatedBrandLogo(size: 110),
              const SizedBox(height: 26),
              ShaderMask(
                shaderCallback: (r) => P.grad.createShader(r),
                child: Text('VARIOUS VPN',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          letterSpacing: 2,
                          fontSize: 22,
                        )),
              ),
              const SizedBox(height: 8),
              Text(L.t('splash_tagline'),
                  style: const TextStyle(color: P.textFaint, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
