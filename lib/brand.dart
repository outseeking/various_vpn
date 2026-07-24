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
  /// Базовый адрес админ-панели (для /vsub, стрика, поддержки и т.п.).
  /// Домен с валидным Let's Encrypt TLS (nginx → панель), без голого IP.
  static const panelBase = 'https://panel.ug-connect.site:2053';
  static const panelSub = '$panelBase/vsub';

  /// Домен-субсервер с валидным TLS: персональная подписка по ID — /vsub/{id}.
  /// Совпадает с SUB_DOMAIN_URL бота (ссылка в «Подключить» из бота).
  static const subDomain = 'https://nl1.ug-connect.site:8088';
  static String subForId(String id) => '$subDomain/vsub/$id';

  /// Единый домен нашей инфраструктуры. Все наши серверы и ссылки-подписки
  /// оканчиваются на него (nl1.ug-connect.site, panel.ug-connect.site, …).
  /// Используется, чтобы в приложение нельзя было добавить подписку чужого VPN.
  static const rootDomain = 'ug-connect.site';
}
