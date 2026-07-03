// Smoke-тест запуска приложения: онбординг рисуется без ошибок.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/screens/onboarding_screen.dart';

void main() {
  testWidgets('Онбординг показывает первый слайд и кнопку «Далее»',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    expect(find.text('Умный авто-роутинг'), findsOneWidget);
    expect(find.text('Далее'), findsOneWidget);
  });
}
