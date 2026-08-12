/// Авто-режим не должен рвать соединение сам.
///
/// В приложении два независимых сторожа: один следит, жив ли туннель, другой
/// ищет сервер побыстрее. Оба умеют пересобирать соединение, и если их не
/// согласовать, они делают это по очереди — человек видит бесконечные
/// переподключения на ровном месте. Здесь закреплены правила, которые это
/// исключают.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:various_vpn/services/backend_api.dart';
import 'package:various_vpn/services/storage.dart';
import 'package:various_vpn/services/vpn_service.dart';
import 'package:various_vpn/state/app_state.dart';

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage.instance;
  await storage.resetForTests();
  return AppState(
      storage: storage, api: BackendApi(), vpnService: StubVpnService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('запрет на переподключение общий у сторожа и авто-выбора', () async {
    // Раньше счётчик был свой у каждого: сторож переключался на тридцатой
    // секунде, авто-выбор — на шестидесятой, и соединение рвалось вдвое чаще,
    // чем разрешено любому из них по отдельности.
    final s = await _app();
    addTearDown(s.dispose);

    expect(s.debugReconnectedRecently, isFalse, reason: 'на старте запрета нет');
    s.debugMarkReconnected();
    expect(s.debugReconnectedRecently, isTrue,
        reason: 'после переподключения оба обязаны выждать');
  });

  test('во время замера сторож молчит, но не забывает', () async {
    // Замер при поднятом туннеле идёт через ядро и занимает его целиком:
    // проба в это время соврёт, поэтому вердикт не выносим. Но и обнулять
    // накопленное нельзя — замеры идут почти непрерывно, и с обнулением
    // мёртвый туннель не заметил бы никто. Ровно это и случилось: приложение
    // показывало «Подключено» при нулевом трафике.
    final s = await _app();
    addTearDown(s.dispose);
    s.debugHealthFails = 1;
    s.debugNoteSweepTick();
    expect(s.debugHealthFails, 1,
        reason: 'иначе непрерывный замер прячет обрыв навсегда');
  });

  test('возврат в приложение обнуляет счётчик неудач', () async {
    // Пока приложение в фоне, Android держит его таймеры остановленными.
    // Всё, что сторож насчитал до этого, к текущему моменту не относится.
    final s = await _app();
    addTearDown(s.dispose);
    s.debugHealthFails = 2;
    s.refreshPingsOnResume();
    expect(s.debugHealthFails, 0);
  });
}
