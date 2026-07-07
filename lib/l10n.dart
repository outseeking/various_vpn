/// Простая локализация RU/EN. `L.current` — текущий язык (ставит AppState).
/// `L.t('key')` возвращает строку. Экраны, читающие AppState через watch,
/// перестраиваются при смене языка.
library;

class L {
  L._();

  /// Текущий язык: 'ru' или 'en'. Устанавливается AppState при старте/смене.
  static String current = 'ru';

  static String t(String key, [Map<String, Object>? params]) {
    final m = _d[key];
    var s = m == null ? key : (m[current] ?? m['ru'] ?? key);
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
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
    'ping_btn': {'ru': 'Пинг', 'en': 'Ping'},
    'ip_auto': {'ru': 'Авто', 'en': 'Auto'},
    'lite_mode': {'ru': 'Режим экономии (слабые устройства)', 'en': 'Lite mode (weak devices)'},
    'lite_mode_d': {
      'ru': 'Отключает падающие звёзды, вращение глобуса и тяжёлые анимации — приложение работает легче и быстрее.',
      'en': 'Disables shooting stars, globe rotation and heavy animations — the app runs lighter and faster.'
    },
    'net_good': {'ru': 'Отличный интернет', 'en': 'Great connection'},
    'net_ok': {'ru': 'Нормальный интернет', 'en': 'Decent connection'},
    'net_slow': {'ru': 'Медленный интернет', 'en': 'Slow connection'},
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

    // --- новые тумблеры/разделы настроек ---
    'adblock': {'ru': 'Блокировка рекламы и трекеров', 'en': 'Ad & tracker blocking'},
    'adblock_d': {
      'ru': 'Режет рекламу, аналитику и трекеры прямо в туннеле — страницы легче, трафика меньше, приватность выше.',
      'en': 'Blocks ads, analytics and trackers right in the tunnel — lighter pages, less traffic, more privacy.'
    },
    'smart_ai': {'ru': 'Умный доступ к ИИ', 'en': 'Smart AI access'},
    'smart_ai_d': {
      'ru': 'ChatGPT, Gemini, Claude и другие нейросети автоматически идут через сервер, где ИИ работает — даже при включённом обходе РФ-сайтов.',
      'en': 'ChatGPT, Gemini, Claude and other AI auto-route through a server where they work — even with RU bypass on.'
    },
    'ondemand': {'ru': 'Режим «По требованию» (On-Demand)', 'en': 'On-Demand mode'},
    'ondemand_d': {
      'ru': 'VPN сам поднимается при запуске приложения и держится наготове — не нужно нажимать «Подключить» каждый раз.',
      'en': 'VPN comes up on app launch and stays ready — no need to tap Connect every time.'
    },
    'mh_nav': {'ru': 'Двойной VPN (мультихоп)', 'en': 'Double VPN (multihop)'},
    'mh_nav_on': {'ru': 'Включён · вход → выход', 'en': 'On · entry → exit'},
    'mh_nav_off': {'ru': 'Цепочка из двух серверов', 'en': 'Chain of two servers'},
    'diag_nav': {'ru': 'Проверить блокировку', 'en': 'Check for blocking'},
    'diag_nav_d': {'ru': 'Диагностика: почему VPN не подключается', 'en': 'Diagnostics: why VPN won\'t connect'},
    'ks_nav': {'ru': 'Kill-switch (защита от утечек)', 'en': 'Kill-switch (leak protection)'},
    'ks_nav_d': {'ru': 'Системная блокировка сети без VPN', 'en': 'System-level block without VPN'},
    'cs_nav': {'ru': 'Свои серверы (JSON)', 'en': 'Custom servers (JSON)'},
    'cs_nav_d': {'ru': 'Для продвинутых · при активном подключении', 'en': 'Advanced · while connected'},

    // --- двойной VPN ---
    'mh_title': {'ru': 'Двойной VPN (мультихоп)', 'en': 'Double VPN (multihop)'},
    'mh_privacy_title': {'ru': 'Максимум приватности', 'en': 'Maximum privacy'},
    'mh_privacy_body': {
      'ru': 'Трафик идёт через две ноды: сначала ВХОД (сервер, к которому ты подключён сейчас), потом ВЫХОД (выбираешь ниже). Входная знает твой IP, но не сайты; выходная видит сайты, но не знает, кто ты.',
      'en': 'Traffic goes through two nodes: first the ENTRY (the server you\'re connected to now), then the EXIT (pick below). The entry knows your IP but not the sites; the exit sees the sites but not who you are.'
    },
    'mh_speed': {
      'ru': 'Скорость будет ниже — это нормально: данные шифруются дважды и проходят лишнюю страну. Для видео и игр лучше обычный режим; двойной — когда важна максимальная анонимность.',
      'en': 'Speed will be lower — that\'s expected: data is encrypted twice and crosses an extra country. For video and games use the normal mode; double is for maximum anonymity.'
    },
    'mh_enable': {'ru': 'Включить двойной VPN', 'en': 'Enable Double VPN'},
    'mh_entry_tag': {'ru': 'ВХОД · текущий сервер', 'en': 'ENTRY · current server'},
    'mh_entry_on': {'ru': 'Подключён — заходишь через эту страну', 'en': 'Connected — you enter via this country'},
    'mh_entry_off': {'ru': 'Подключись на главном экране', 'en': 'Connect on the home screen'},
    'mh_no_server': {'ru': 'Сервер не выбран', 'en': 'No server selected'},
    'mh_exit_label': {'ru': 'Выход (его страну видят сайты):', 'en': 'Exit (sites see its country):'},
    'mh_need_two': {'ru': 'Нужно минимум два сервера для цепочки.', 'en': 'Need at least two servers for a chain.'},
    'mh_route': {'ru': 'Маршрут', 'en': 'Route'},
    'mh_pick_exit': {'ru': 'выбери выход', 'en': 'pick exit'},
    'mh_footer': {
      'ru': 'Вход меняется на главном экране (это твой текущий сервер). Здесь выбираешь только выход.',
      'en': 'The entry is changed on the home screen (it\'s your current server). Here you only pick the exit.'
    },

    // --- диагностика ---
    'diag_title': {'ru': 'Проверить блокировку', 'en': 'Check for blocking'},
    'diag_intro': {
      'ru': 'Проверяем, почему VPN может не подключаться. Все пробы идут в обход туннеля — так видно реальную картину сети.',
      'en': 'We check why the VPN may not connect. All probes go outside the tunnel to show the real network picture.'
    },
    'diag_s_net': {'ru': 'Интернет доступен', 'en': 'Internet available'},
    'diag_s_tcp': {'ru': 'Сервер отвечает (TCP)', 'en': 'Server responds (TCP)'},
    'diag_s_tls': {'ru': 'TLS-рукопожатие проходит', 'en': 'TLS handshake passes'},
    'diag_s_tun': {'ru': 'Трафик идёт через туннель', 'en': 'Traffic flows via tunnel'},
    'diag_retry': {'ru': 'Проверить снова', 'en': 'Check again'},
    'diag_running': {'ru': 'Проверяю…', 'en': 'Checking…'},
    'diag_v_nonet': {'ru': 'Нет интернета. Проверь Wi-Fi/мобильные данные — VPN тут ни при чём.', 'en': 'No internet. Check Wi-Fi/mobile data — the VPN isn\'t the issue.'},
    'diag_v_nosrv': {'ru': 'Сначала импортируй подписку — серверов для проверки нет.', 'en': 'Import a subscription first — no servers to test.'},
    'diag_v_tcp': {'ru': 'Сервер недоступен по сети: либо узел лежит, либо провайдер блокирует его IP. Попробуй другой сервер.', 'en': 'Server unreachable: the node is down or your ISP blocks its IP. Try another server.'},
    'diag_v_tls': {'ru': 'TCP проходит, но TLS-рукопожатие сбрасывается — признак DPI-блокировки протокола провайдером. Помогают фрагментация и смена сервера.', 'en': 'TCP passes but the TLS handshake is reset — a sign of DPI protocol blocking by your ISP. Fragmentation and switching servers help.'},
    'diag_v_tun': {'ru': 'Связь с сервером есть, но туннель не пропускает трафик — переподключись; если повторяется, смени сервер.', 'en': 'The server is reachable but the tunnel passes no traffic — reconnect; if it repeats, switch servers.'},
    'diag_v_ok': {'ru': 'Всё в порядке ✅ Сервер доступен и протокол не блокируется.', 'en': 'All good ✅ The server is reachable and the protocol isn\'t blocked.'},
    'diag_ok': {'ru': 'есть', 'en': 'ok'},
    'diag_nonet': {'ru': 'нет соединения с сетью', 'en': 'no network connection'},
    'diag_port_open': {'ru': 'порт открыт', 'en': 'port open'},
    'diag_port_closed': {'ru': 'порт не отвечает', 'en': 'port not responding'},
    'diag_tls_ok': {'ru': 'рукопожатие ок', 'en': 'handshake ok'},
    'diag_tls_dpi': {'ru': 'TLS сбрасывается (похоже на DPI)', 'en': 'TLS reset (looks like DPI)'},
    'diag_tun_ok': {'ru': 'работает', 'en': 'works'},
    'diag_tun_fail': {'ru': 'нет ответа через туннель', 'en': 'no response via tunnel'},
    'diag_tun_skip': {'ru': 'VPN не подключён — пропущено', 'en': 'VPN not connected — skipped'},
    'diag_no_srv2': {'ru': 'нет выбранного сервера', 'en': 'no server selected'},

    // --- kill-switch ---
    'ks_title': {'ru': 'Kill-switch (защита от утечек)', 'en': 'Kill-switch (leak protection)'},
    'ks_intro': {
      'ru': 'Настоящий Kill-switch — это системная функция Android. Она блокирует весь интернет, если VPN отключился, и работает даже при перезапуске или сбое приложения.',
      'en': 'A real kill-switch is an Android system feature. It blocks all internet if the VPN drops and works even if the app restarts or crashes.'
    },
    'ks_how': {'ru': 'Как включить:', 'en': 'How to enable:'},
    'ks_s1': {'ru': 'Нажми кнопку ниже — откроются настройки VPN.', 'en': 'Tap the button below — VPN settings will open.'},
    'ks_s2': {'ru': 'Возле «Various VPN» нажми ⚙️ (шестерёнку).', 'en': 'Next to “Various VPN” tap ⚙️ (the gear).'},
    'ks_s3': {'ru': 'Включи «Постоянная VPN» (Always-on VPN).', 'en': 'Turn on “Always-on VPN”.'},
    'ks_s4': {'ru': 'Включи «Блокировать соединения без VPN».', 'en': 'Turn on “Block connections without VPN”.'},
    'ks_open': {'ru': 'Открыть настройки VPN', 'en': 'Open VPN settings'},
    'ks_hint': {
      'ru': 'Подсказка: для «Постоянной VPN» подключение должно быть настроено — сначала хотя бы раз подключись к Various VPN.',
      'en': 'Tip: for Always-on VPN a connection must exist — connect to Various VPN at least once first.'
    },

    // --- свои серверы ---
    'cs_title': {'ru': 'Свои серверы', 'en': 'Custom servers'},
    'cs_advanced': {'ru': 'Для продвинутых', 'en': 'For advanced users'},
    'cs_body': {
      'ru': 'Можно добавить до 5 собственных серверов через JSON — они появятся рядом с нашими. Это личная настройка и доступна только когда ты подключён к Various VPN.',
      'en': 'You can add up to 5 of your own servers via JSON — they\'ll appear next to ours. This is a personal setting, available only while connected to Various VPN.'
    },
    'cs_locked': {'ru': 'Сначала подключись к Various VPN — потом добавление откроется.', 'en': 'Connect to Various VPN first — then adding unlocks.'},
    'cs_paste': {'ru': 'Вставить из буфера', 'en': 'Paste from clipboard'},
    'cs_add': {'ru': 'Добавить серверы', 'en': 'Add servers'},
    'cs_added': {'ru': '✅ Свои серверы добавлены', 'en': '✅ Custom servers added'},

    // --- стрик / огонёк ---
    'streak_title_on': {'ru': 'Серия: {n} дней подряд', 'en': 'Streak: {n} days in a row'},
    'streak_title_off': {'ru': 'Начни серию!', 'en': 'Start a streak!'},
    'streak_hint_on': {'ru': 'Заходи каждый день — не потеряй огонёк 🔥', 'en': 'Come back daily — don\'t lose the flame 🔥'},
    'streak_hint_off': {'ru': 'Подключай VPN каждый день и получай бонусные дни', 'en': 'Connect the VPN daily and earn bonus days'},
    'streak_next': {'ru': 'До награды +{r} дней: осталось {d} дн. (веха {m})', 'en': 'To reward +{r} days: {d} days left (milestone {m})'},
    'streak_freezes': {'ru': 'Заморозки: {n} · копятся за 25+ ч VPN в неделю и спасают серию при пропуске дня', 'en': 'Freezes: {n} · earned for 25+ h VPN a week, save your streak if you miss a day'},
    'streak_rewards': {'ru': 'Награды за серию', 'en': 'Streak rewards'},
    'streak_celebrate': {'ru': 'СЕРИЯ ПРОДОЛЖАЕТСЯ!', 'en': 'STREAK CONTINUES!'},
    'streak_celebrate_sub': {'ru': '{n} дней подряд с Various VPN', 'en': '{n} days in a row with Various VPN'},
    'streak_reward_days': {'ru': '🎁  +{n} дней подписки', 'en': '🎁  +{n} subscription days'},
    'streak_close': {'ru': 'Начислено автоматически · тапни, чтобы закрыть', 'en': 'Credited automatically · tap to close'},
  };
}
