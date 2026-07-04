/// Внешние ссылки бренда Various VPN. Если хэндл канала другой — поправь здесь.
library;

class Brand {
  Brand._();
  static const bot = 'https://t.me/variousvpnbot';
  static const channel = 'https://t.me/variousvpn'; // новостной канал (уточнить)
  static const support = 'https://t.me/variousvpnbot'; // поддержка через бота

  /// Подписка из админ-панели: добавил сервер в панели → он появляется здесь.
  /// Панель отдаёт /vsub (base64 список включённых серверов). Поменяй на свой
  /// адрес после разворачивания панели (домен/поддомен → VPS с панелью).
  /// Базовый адрес админ-панели (для /vsub, поддержки и т.п.).
  static const panelBase = 'https://panel.ug-connect.site:9443';
  static const panelSub = '$panelBase/vsub';

  /// Единый домен нашей инфраструктуры. Все наши серверы и ссылки-подписки
  /// оканчиваются на него (nl1.ug-connect.site, panel.ug-connect.site, …).
  /// Используется, чтобы в приложение нельзя было добавить подписку чужого VPN.
  static const rootDomain = 'ug-connect.site';
}
