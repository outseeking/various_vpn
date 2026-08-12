/// Точка входа только для витрины стиля iOS.
///
/// Отдельная от основной намеренно. Обычный запуск ведёт через онбординг и
/// вход по подписке — до настроек, где живёт витрина, так просто не добраться,
/// а смотреть надо именно на элементы. Здесь приложение открывается сразу на
/// них.
///
/// Собирается как обычная веб-сборка:
///   flutter build web -t lib/main_ios_preview.dart -o build/web-ios
library;

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'screens/ios_preview_screen.dart';
import 'theme/app_theme.dart';

void main() {
  L.current = 'ru';
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Various VPN · стиль iOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const IosPreviewScreen(),
    );
  }
}
