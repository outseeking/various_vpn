/// Простая локализация RU/EN. `L.current` — текущий язык (ставит AppState).
/// `L.t('key')` возвращает строку. Экраны, читающие AppState через watch,
/// перестраиваются при смене языка.
library;

class L {
  L._();

  /// Текущий язык: 'ru' или 'en'. Устанавливается AppState при старте/смене.
  static String current = 'ru';

  static String t(String key) {
    final m = _d[key];
    if (m == null) return key;
    return m[current] ?? m['ru'] ?? key;
  }

  static const Map<String, Map<String, String>> _d = {
    // --- онбординг ---
    'ob1_title': {'ru': 'Умный авто-роутинг', 'en': 'Smart auto-routing'},
    'ob1_body': {
      'ru': 'Каждое приложение идёт через свою страну. ИИ сам выбирает лучший рабочий сервер по пингу.',
      'en': 'Each app goes through its own country. AI picks the best working server by ping.'
    },
    'ob2_title': {'ru': 'Россия — напрямую', 'en': 'Russia — direct'},
    'ob2_body': {
      'ru': 'Банки, госуслуги и локальные сайты работают без VPN и без потери скорости. Туннель — только где нужно.',
      'en': 'Banks, government and local sites work without VPN and without speed loss. Tunnel only where needed.'
    },
    'ob3_title': {'ru': 'Современные протоколы', 'en': 'Modern protocols'},
    'ob3_body': {
      'ru': 'VLESS, Reality и другие — быстро, стабильно и незаметно для блокировок. Видно, что и через какой сервер идёт.',
      'en': 'VLESS, Reality and more — fast, stable and invisible to blocks. See what goes through which server.'
    },
    'skip': {'ru': 'Пропустить', 'en': 'Skip'},
    'next': {'ru': 'Далее', 'en': 'Next'},
    'start': {'ru': 'Начать', 'en': 'Start'},

    // --- главный экран ---
    'protected': {'ru': 'Подключено', 'en': 'Connected'},
    'disconnected': {'ru': 'Отключено', 'en': 'Disconnected'},
    'connecting': {'ru': 'Подключение…', 'en': 'Connecting…'},
    'ai_auto': {'ru': 'ИИ · авто', 'en': 'AI · auto'},
    'manual': {'ru': 'Ручной', 'en': 'Manual'},
    'mode_hint_ai': {
      'ru': 'ИИ сам выбирает лучший сервер по пингу',
      'en': 'AI picks the best server by ping'
    },
    'mode_hint_manual': {
      'ru': 'Выбери сервер вручную — тапни по стране ниже',
      'en': 'Pick a server manually — tap a country below'
    },
    'ping': {'ru': 'пинг', 'en': 'ping'},
    'servers': {'ru': 'Серверы', 'en': 'Servers'},
    'ping_btn': {'ru': 'Пинговать', 'en': 'Ping'},
    'no_server': {'ru': 'Нет сервера', 'en': 'No server'},
    'free_tg': {'ru': 'Бесплатно · Telegram', 'en': 'Free · Telegram'},
    'free_tg_sub': {'ru': 'Только трафик Telegram', 'en': 'Telegram traffic only'},
    'import_hint': {'ru': 'Импортируй подписку', 'en': 'Import subscription'},
    'no_servers': {'ru': 'Нет серверов', 'en': 'No servers'},
    'no_servers_sub': {
      'ru': 'Импортируй подписку из бота',
      'en': 'Import a subscription from the bot'
    },
    'traffic_via': {'ru': 'Трафик идёт через VPN', 'en': 'Traffic goes via VPN'},

    // --- сессия ---
    'time': {'ru': 'Время', 'en': 'Time'},
    'downloaded': {'ru': 'Скачано', 'en': 'Downloaded'},
    'uploaded': {'ru': 'Отдано', 'en': 'Uploaded'},

    // --- настройки ---
    'settings': {'ru': 'Настройки', 'en': 'Settings'},
    'sec_account': {'ru': 'Аккаунт', 'en': 'Account'},
    'sec_connection': {'ru': 'Подключение', 'en': 'Connection'},
    'sec_interface': {'ru': 'Интерфейс', 'en': 'Interface'},
    'sec_notifications': {'ru': 'Уведомления', 'en': 'Notifications'},
    'sec_extra': {'ru': 'Дополнительно', 'en': 'More'},
    'sec_admin': {'ru': 'Администрирование', 'en': 'Administration'},
    'profile_sub': {'ru': 'Профиль и подписка', 'en': 'Profile & subscription'},
    'profile_sub_d': {'ru': 'Статус, продление, рефералка', 'en': 'Status, renew, referral'},
    'channel': {'ru': 'Наш Telegram-канал', 'en': 'Our Telegram channel'},
    'channel_d': {'ru': 'Новости и статусы серверов', 'en': 'News and server status'},
    'autoconnect': {'ru': 'Автоподключение при запуске', 'en': 'Auto-connect on launch'},
    'autoconnect_d': {'ru': 'Включать VPN сразу при открытии', 'en': 'Turn on VPN right at startup'},
    'killswitch': {'ru': 'Kill-switch', 'en': 'Kill-switch'},
    'killswitch_d': {'ru': 'Блокировать трафик при обрыве VPN', 'en': 'Block traffic if VPN drops'},
    'bypass_ru': {'ru': 'Обход для РФ-сайтов', 'en': 'Bypass for RU sites'},
    'bypass_ru_d': {'ru': 'Локальные ресурсы — напрямую, мимо VPN', 'en': 'Local resources go direct, bypassing VPN'},
    'per_app': {'ru': 'Раздельно по приложениям', 'en': 'Per-app routing'},
    'protocol': {'ru': 'Протокол', 'en': 'Protocol'},
    'dns': {'ru': 'DNS', 'en': 'DNS'},
    'language': {'ru': 'Язык', 'en': 'Language'},
    'globe_anim': {'ru': 'Анимации глобуса', 'en': 'Globe animations'},
    'globe_anim_d': {'ru': 'Вращение, пакеты, наезд при подключении', 'en': 'Rotation, packets, zoom on connect'},
    'sound': {'ru': 'Звук подключения', 'en': 'Connection sound'},
    'sound_d': {'ru': 'Звук при подключении и отключении', 'en': 'Sound on connect and disconnect'},
    'vibration': {'ru': 'Вибрация', 'en': 'Vibration'},
    'vibration_d': {'ru': 'Виброотклик при подключении', 'en': 'Haptic feedback on connect'},
    'notif_server': {'ru': 'Смена сервера / статус', 'en': 'Server change / status'},
    'notif_server_d': {'ru': 'Подключение, переключение, алерты', 'en': 'Connect, switch, alerts'},
    'stats': {'ru': 'Статистика', 'en': 'Statistics'},
    'stats_d': {'ru': 'Трафик за всё время, страны, графики', 'en': 'All-time traffic, countries, charts'},
    'speedtest': {'ru': 'Тест скорости', 'en': 'Speed test'},
    'speedtest_d': {'ru': 'Замер скорости со спидометром', 'en': 'Speed measurement with a gauge'},
    'how_connect': {'ru': 'Как подключиться', 'en': 'How to connect'},
    'how_connect_d': {'ru': 'Инструкция по подключению VPN', 'en': 'VPN connection guide'},
    'logs': {'ru': 'Логи (что → куда идёт)', 'en': 'Logs (what goes where)'},
    'update_sub': {'ru': 'Обновить / импортировать подписку', 'en': 'Update / import subscription'},
    'support': {'ru': 'Поддержка', 'en': 'Support'},
    'support_d': {'ru': 'Чат в приложении или Telegram', 'en': 'In-app chat or Telegram'},
    'admin_panel': {'ru': 'Админ-панель', 'en': 'Admin panel'},
    'admin_panel_d': {'ru': 'Метрики, ошибки, ИИ-агент', 'en': 'Metrics, errors, AI agent'},
    'logout': {'ru': 'Выйти из аккаунта', 'en': 'Log out'},

    // --- профиль ---
    'profile': {'ru': 'Профиль', 'en': 'Profile'},
    'account_not_linked': {'ru': 'Аккаунт не привязан', 'en': 'Account not linked'},
    'sub_active': {'ru': 'Подписка активна', 'en': 'Subscription active'},
    'sub_inactive': {'ru': 'Подписка не активна', 'en': 'Subscription inactive'},
    'full_access': {'ru': 'Полный доступ ко всем серверам', 'en': 'Full access to all servers'},
    'subscribe_hint': {'ru': 'Оформи в боте для полного доступа', 'en': 'Subscribe in the bot for full access'},
    'renew': {'ru': 'Продлить подписку', 'en': 'Renew subscription'},
    'subscribe': {'ru': 'Оформить подписку', 'en': 'Get subscription'},
    'invite': {'ru': 'Пригласить друга', 'en': 'Invite a friend'},
    'invite_d': {'ru': 'Реферальная ссылка и бонусы в боте', 'en': 'Referral link and bonuses in the bot'},
    'copy_id': {'ru': 'Скопировать Telegram ID', 'en': 'Copy Telegram ID'},
    'valid_until': {'ru': 'Действует до', 'en': 'Valid until'},
    'link_tg': {'ru': 'Привязать Telegram', 'en': 'Link Telegram'},
    'link_tg_d': {'ru': 'Синхронизировать подписку и статус', 'en': 'Sync subscription and status'},
    'link_tg_hint': {
      'ru': 'Введи свой Telegram ID (узнать можно в нашем боте).',
      'en': 'Enter your Telegram ID (get it from our bot).'
    },
    'cancel': {'ru': 'Отмена', 'en': 'Cancel'},
    'save': {'ru': 'Сохранить', 'en': 'Save'},

    // --- пинг ---
    'ping_settings': {'ru': 'Настройки пинга', 'en': 'Ping settings'},
    'ping_type': {'ru': 'Тип пинга', 'en': 'Ping type'},
    'ping_proxy_d': {'ru': 'Точнее — реальная задержка через туннель', 'en': 'More accurate — real latency via tunnel'},
    'ping_tcp_d': {'ru': 'Быстрее — время TCP-хендшейка до сервера', 'en': 'Faster — TCP handshake time to server'},
    'ping_test_url': {'ru': 'Тестовый URL (via Proxy)', 'en': 'Test URL (via Proxy)'},

    // --- сеть ---
    'net_settings': {'ru': 'Сеть и протокол', 'en': 'Network & protocol'},
    'net_settings_d': {'ru': 'IPv4/IPv6, DNS, фрагментация', 'en': 'IPv4/IPv6, DNS, fragmentation'},
    'ip_type': {'ru': 'Тип адресов (IPv4 / IPv6)', 'en': 'Address type (IPv4 / IPv6)'},
    'ip_type_hint': {
      'ru': 'IPv4 — максимальная совместимость. IPv6 — если провайдер поддерживает. Менять только если понимаете, что делаете.',
      'en': 'IPv4 — max compatibility. IPv6 — if your ISP supports it. Change only if you know what you are doing.'
    },
    'custom_dns': {'ru': 'Свой DNS', 'en': 'Custom DNS'},
    'custom_dns_hint': {
      'ru': 'Через запятую. Пусто — DNS сервера по умолчанию. Менять только если понимаете, что делаете.',
      'en': 'Comma-separated. Empty — server default DNS. Change only if you know what you are doing.'
    },
    'fragment': {'ru': 'Фрагментация TLS', 'en': 'TLS fragmentation'},
    'fragment_d': {
      'ru': 'Дробит TLS-пакеты для обхода блокировок (DPI). Включай, если провайдер режет VPN.',
      'en': 'Splits TLS packets to bypass DPI blocking. Enable if your ISP throttles VPN.'
    },

    // --- выход ---
    'logout_q': {'ru': 'Выйти?', 'en': 'Log out?'},
    'logout_body': {
      'ru': 'Сотрём подписку и настройки на этом устройстве.',
      'en': 'We will erase the subscription and settings on this device.'
    },
    'ping_label': {'ru': 'Пинг', 'en': 'Ping'},

    // --- туннелирование (split) ---
    'tunneling': {'ru': 'Туннелирование', 'en': 'Tunneling'},
    'search': {'ru': 'Поиск', 'en': 'Search'},
    'split_enable': {'ru': 'Включить туннелирование трафика', 'en': 'Enable split tunneling'},
    'split_hint_through': {
      'ru': 'Выбранные приложения идут через VPN, остальные — напрямую.',
      'en': 'Selected apps go through VPN, the rest go direct.'
    },
    'split_hint_bypass': {
      'ru': 'Выбранные приложения идут напрямую, остальные — через VPN.',
      'en': 'Selected apps go direct, the rest go through VPN.'
    },
    'split_bypass': {'ru': 'В обход VPN', 'en': 'Bypass VPN'},
    'split_bypass_sub': {'ru': 'Остальное — через VPN', 'en': 'Rest — through VPN'},
    'split_through': {'ru': 'Через VPN', 'en': 'Through VPN'},
    'split_through_sub': {'ru': 'Остальное — напрямую', 'en': 'Rest — direct'},
    'split_no_apps': {
      'ru': 'Список приложений доступен только на устройстве Android.',
      'en': 'App list is available only on an Android device.'
    },
    'tab_apps': {'ru': 'Приложения', 'en': 'Apps'},
    'tab_urls': {'ru': 'Сайты (URL)', 'en': 'Sites (URL)'},
    'url_hint': {
      'ru': 'Эти сайты будут открываться напрямую, минуя VPN (как «белые» сайты в Quattro).',
      'en': 'These sites open directly, bypassing the VPN.'
    },
    'url_your': {'ru': 'Ваши сайты', 'en': 'Your sites'},
    'url_popular': {'ru': 'Популярные', 'en': 'Popular'},
  };
}
