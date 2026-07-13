/// Синхронизация состояния VPN с домашним виджетом Android (home_widget).
/// Пишет в SharedPreferences виджета статус/сервер/подписи/яркий флаг и данные,
/// которые нативный [VariousWidgetActionReceiver] использует, чтобы включать/
/// выключать VPN и мерить пинг БЕЗ открытия приложения.
/// На web/не-Android — безопасные no-op.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../l10n.dart';
import '../widgets/flag.dart';

class HomeWidgetSync {
  HomeWidgetSync._();

  static const _android = 'VariousWidgetProvider';
  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android);
  static String _lastFlagCc = '';

  /// Толкнуть актуальное состояние в виджет.
  static Future<void> push({
    required bool connected,
    required String countryCode,
    required String server,
    String host = '',
    int port = 0,
    String pingType = 'tcp',
    int pingMs = -1,
  }) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>(
          'vv_connected', connected ? 'true' : 'false');
      await HomeWidget.saveWidgetData<String>(
          'vv_status', connected ? L.t('protected') : L.t('disconnected'));
      await HomeWidget.saveWidgetData<String>('vv_server', server);
      await HomeWidget.saveWidgetData<String>(
          'vv_ping', pingMs > 0 ? '$pingMs ms' : '');
      await HomeWidget.saveWidgetData<String>(
          'vv_button', connected ? L.t('wdg_disconnect') : L.t('wdg_connect'));

      // Локализованные подписи — их подставляет нативный ресивер при toggle.
      await HomeWidget.saveWidgetData<String>('vv_lbl_protected', L.t('protected'));
      await HomeWidget.saveWidgetData<String>('vv_lbl_disconnected', L.t('disconnected'));
      await HomeWidget.saveWidgetData<String>('vv_lbl_connect', L.t('wdg_connect'));
      await HomeWidget.saveWidgetData<String>('vv_lbl_disconnect', L.t('wdg_disconnect'));

      // Параметры замера пинга (как в приложении: tcp / tls-хендшейк).
      if (host.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('vv_ping_host', host);
        await HomeWidget.saveWidgetData<int>('vv_ping_port', port);
        await HomeWidget.saveWidgetData<String>('vv_ping_type', pingType);
      }

      // Яркий флаг в стиле приложения (рисуем в bitmap один раз на страну).
      if (countryCode.isNotEmpty && countryCode != _lastFlagCc) {
        _lastFlagCc = countryCode;
        await HomeWidget.renderFlutterWidget(
          Container(
            color: const Color(0xFF0F1A2E),
            padding: const EdgeInsets.all(4),
            child: CountryFlag(countryCode, width: 72),
          ),
          key: 'vv_flag_img',
          logicalSize: const Size(80, 60),
          pixelRatio: 3,
        );
      }

      await HomeWidget.updateWidget(androidName: _android);
    } catch (_) {
      // виджет может быть не добавлен — это нормально
    }
  }

  /// Сохранить последний рабочий конфиг — нативный ресивер поднимет по нему VPN
  /// при нажатии «Подключить» в виджете (без открытия приложения).
  static Future<void> saveConnectConfig({
    required String config,
    required String remark,
    List<String> blockedApps = const [],
  }) async {
    if (!_supported) return;
    try {
      await HomeWidget.saveWidgetData<String>('vv_config', config);
      await HomeWidget.saveWidgetData<String>('vv_remark', remark);
      await HomeWidget.saveWidgetData<String>(
          'vv_blocked', blockedApps.join('\n'));
    } catch (_) {}
  }
}
