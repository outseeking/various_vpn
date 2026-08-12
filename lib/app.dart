/// Корень приложения: MaterialApp, тема (светлая/тёмная по системе) и выбор
/// стартового экрана по сохранённому состоянию.
library;

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'services/storage.dart';
import 'theme/app_theme.dart';

class VariousVpnApp extends StatelessWidget {
  const VariousVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = Storage.instance;
    // Порядок первого запуска: сплеш → онбординг (слайды про плюсы) → вход.
    // Шага с офертой больше нет: документы живут в боте, и отдельный экран
    // с согласием при первом запуске только отпугивал — человек ещё ничего не
    // получил, а от него уже чего-то требуют.
    final Widget home;
    if (!storage.onboardingDone) {
      home = const OnboardingScreen();
    } else if (storage.subUrl != null || storage.tgId != null) {
      home = const MainShell();
    } else {
      home = const OnboardingScreen();
    }

    // Приложение фирменно тёмное: глобус, неон-акценты и переливание
    // рассчитаны на тёмный фон. Светлая тема выглядела бы чужеродно, поэтому
    // фиксируем тёмную (светлую сделаем отдельным дизайн-этапом при желании).
    return MaterialApp(
      title: 'Various VPN',
      debugShowCheckedModeBanner: false,
      // Шрифт задаётся ключом — так его можно поменять одной строкой,
      // не трогая тему.
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: SplashScreen(next: home),
    );
  }
}
