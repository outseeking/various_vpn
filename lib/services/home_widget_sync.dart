/// Синхронизация состояния VPN с домашним виджетом Android (home_widget).
/// Пишет в SharedPreferences виджета статус/сервер/подписи/яркий флаг и данные,
/// которые нативный [VariousWidgetActionReceiver] использует, чтобы включать/
/// выключать VPN и мерить пинг БЕЗ открытия приложения.
/// На iOS — тот же набор ключей через общую группу (App Group).
/// На web и прочих платформах — безопасные no-op.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../l10n.dart';
import '../widgets/flag.dart';
import 'storage.dart';

class HomeWidgetSync {
  HomeWidgetSync._();

  static const _android = 'VariousWidgetProvider';
  static const _ios = 'VariousStatusWidget';

  /// Общая группа приложения и его расширений. На iOS процессы разные, общей
  /// памяти нет — состояние передаётся только через неё. На Android параметр
  /// не используется, поэтому задаётся один раз при старте.
  static const _group = 'group.com.example.variousVpn';

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool _groupSet = false;
  static String _lastFlagCc = '';

  /// Группу достаточно задать однажды за запуск, но вызывается это из разных
  /// мест — проще запомнить, чем следить за порядком.
  static Future<void> _ensureGroup() async {
    if (!_isIos || _groupSet) return;
    _groupSet = true;
    await HomeWidget.setAppGroupId(_group);
  }

  /// Обновить нужный виджет. Имена у систем разные: на Android это класс
  /// провайдера, на iOS — «вид» из WidgetKit.
  static Future<void> _update() =>
      HomeWidget.updateWidget(androidName: _android, iOSName: _ios);

  /// Обновить ТОЛЬКО значок виджета — сразу после смены иконки приложения.
  /// Ждать очередного изменения состояния VPN нельзя: человек поменял иконку и
  /// должен увидеть результат на домашнем экране немедленно.
  static Future<void> refreshIcon(String key) async {
    if (!_supported) return;
    try {
      await _ensureGroup();
      await HomeWidget.saveWidgetData<String>('vv_icon', key);
      await _update();
    } catch (_) {
      // виджет может быть не добавлен на экран — это не ошибка
    }
  }

  /// Толкнуть актуальное состояние в виджет.
  static Future<void> push({
    required bool connected,
    required String countryCode,
    required String server,
    String host = '',
    int port = 0,
    String pingType = 'tcp',
    int pingMs = -1,
    bool telegramOnly = false,
  }) async {
    if (!_supported) return;
    try {
      await _ensureGroup();
      // Виджет носит тот же значок, что и сама иконка приложения: сменил
      // иконку — сменился и он, иначе на экране рядом два разных логотипа.
      await HomeWidget.saveWidgetData<String>(
          'vv_icon', Storage.instance.getStr('app_icon', def: 'classic'));
      await HomeWidget.saveWidgetData<String>(
          'vv_connected', connected ? 'true' : 'false');
      await HomeWidget.saveWidgetData<String>(
          'vv_status', connected ? L.t('protected') : L.t('disconnected'));
      // В бесплатном режиме сервер выбирается автоматически и работает только
      // Telegram — так и подписываем, вместо имени конкретной страны. Пинг там
      // не показываем (мерить нечего: конфиг подбирается сам).
      await HomeWidget.saveWidgetData<String>(
          'vv_server', telegramOnly ? L.t('wdg_auto_tg') : server);
      await HomeWidget.saveWidgetData<String>(
          'vv_free', telegramOnly ? 'true' : 'false');
      // Есть ли вообще выбранный сервер: если нет — прячем флаг, иначе рядом
      // с «Сервер не выбран» висел флаг прошлой страны и это путало.
      await HomeWidget.saveWidgetData<String>(
          'vv_has_server', countryCode.isNotEmpty ? 'true' : 'false');
      await HomeWidget.saveWidgetData<String>(
          'vv_ping', (telegramOnly || pingMs <= 0) ? '' : '$pingMs ms');
      // Код страны — для флага в виджете iOS: там он рисуется системным
      // эмодзи, а не картинкой, поэтому нужен сам код, а не готовый снимок.
      await HomeWidget.saveWidgetData<String>('vv_cc', countryCode);
      await HomeWidget.saveWidgetData<String>(
          'vv_button', connected ? L.t('wdg_disconnect') : L.t('wdg_connect'));

      // Локализованные подписи — их подставляет нативный ресивер при toggle.
      await HomeWidget.saveWidgetData<String>(
          'vv_lbl_protected', L.t('protected'));
      await HomeWidget.saveWidgetData<String>(
          'vv_lbl_disconnected', L.t('disconnected'));
      await HomeWidget.saveWidgetData<String>(
          'vv_lbl_connect', L.t('wdg_connect'));
      await HomeWidget.saveWidgetData<String>(
          'vv_lbl_disconnect', L.t('wdg_disconnect'));

      // Параметры замера пинга (как в приложении: tcp / tls-хендшейк).
      if (host.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>('vv_ping_host', host);
        await HomeWidget.saveWidgetData<int>('vv_ping_port', port);
        await HomeWidget.saveWidgetData<String>('vv_ping_type', pingType);
      }

      // Яркий флаг в стиле приложения (рисуем в bitmap один раз на страну).
      // Только Android: на iOS флаг рисует система по коду страны — снимок
      // виджета там не нужен и лишний раз будил бы движок отрисовки.
      if (!_isIos && countryCode.isNotEmpty && countryCode != _lastFlagCc) {
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

      await _update();
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
    // Только Android: там нативный ресивер поднимает VPN прямо из виджета. На
    // iOS кнопки в виджете нет — система не даёт расширению запускать туннель,
    // и хранить ради этого конфиг в общей группе было бы лишним риском.
    if (!_supported || _isIos) return;
    try {
      await HomeWidget.saveWidgetData<String>('vv_config', config);
      await HomeWidget.saveWidgetData<String>('vv_remark', remark);
      await HomeWidget.saveWidgetData<String>(
          'vv_blocked', blockedApps.join('\n'));
    } catch (_) {}
  }
}
