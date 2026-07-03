/// Модели для уведомлений и журнала маршрутизации (что→куда идёт).
///
/// По APP_LOGIC.md: §3 — маленькое уведомление при авто-переключении сервера;
/// §1a — алерт «VPN не работает»; §8 — напоминание об окончании подписки;
/// §10 — push-новости. Здесь — данные; показ в приложении (NotificationsScreen)
/// + позже реальный push (FCM/APNs) на мобильной сборке.
library;

import 'package:flutter/material.dart';

enum NotifKind {
  serverSwitch, // ИИ переключил сервер
  vpnDown, // все сервера недоступны
  expiry, // подписка скоро кончится / кончилась
  news, // новости/акции
  info; // прочее

  IconData get icon => switch (this) {
        NotifKind.serverSwitch => Icons.swap_horiz,
        NotifKind.vpnDown => Icons.error_outline,
        NotifKind.expiry => Icons.schedule,
        NotifKind.news => Icons.campaign,
        NotifKind.info => Icons.info_outline,
      };
}

class AppNotification {
  final NotifKind kind;
  final String title;
  final String body;
  final DateTime at;

  AppNotification({
    required this.kind,
    required this.title,
    required this.body,
    DateTime? at,
  }) : at = at ?? DateTime.now();
}

/// Одна запись журнала маршрутизации: когда, что (приложение), куда (сервер).
class RouteLogEntry {
  final DateTime at;
  final String app;
  final String target; // имя сервера или «Напрямую»
  final String flag;
  final String action; // напр. «подключено», «переключено», «напрямую»

  RouteLogEntry({
    required this.app,
    required this.target,
    this.flag = '🌐',
    this.action = '',
    DateTime? at,
  }) : at = at ?? DateTime.now();
}
