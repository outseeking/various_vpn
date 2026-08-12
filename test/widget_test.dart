/// Онбординг: первый экран рисуется и ведёт в оффер.
///
/// Тест переписан вместе с самим онбордингом: раньше он проверял слайд
/// «Добро пожаловать в Various VPN», которого больше нет — семь длинных
/// слайдов заменены пятью короткими, и последний обещает 3 дня бесплатно.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/screens/onboarding_screen.dart';
import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';
import 'package:various_vpn/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('GoogleFonts')) return;
      prev?.call(d);
    };
  });

  testWidgets('онбординг начинается с оффера, а не с инструкции',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = Storage.instance;
    await storage.resetForTests();
    final state = AppState(
      storage: storage,
      api: BackendApi(),
      vpnService: StubVpnService(),
    );

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: AppTheme.dark(), home: const OnboardingScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Первый слайд — короткое обещание, а не «добро пожаловать».
    expect(find.text('Интернет без границ'), findsOneWidget);
    // Переключатель языка доступен с первого экрана.
    expect(find.text('RU'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    state.dispose();
  });
}
