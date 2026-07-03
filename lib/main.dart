/// Точка входа Various VPN. Инициализирует хранилище, поднимает центральное
/// состояние и отдаёт его всему дереву через provider.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/backend_api.dart';
import 'services/storage.dart';
import 'services/vpn_core.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Storage.instance.init();

  // Ядро выбирается по платформе: web → заглушка, Android/iOS → flutter_v2ray
  // (см. services/vpn_core.dart). Интерфейс один и тот же.
  final state = AppState(
    storage: Storage.instance,
    api: BackendApi(),
    vpnService: createVpnService(),
  );
  await state.bootstrap();

  // Автоподключение при запуске (если включено в настройках и есть серверы).
  if (state.autoConnect && state.hasServers) {
    // не блокируем старт UI — подключаемся в фоне
    Future.microtask(state.connect);
  }

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const VariousVpnApp(),
    ),
  );
}
