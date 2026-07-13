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
    'update_short': {'ru': 'Обновить', 'en': 'Update'},
    'sub_actions_title': {'ru': 'Уже есть подписка?', 'en': 'Already subscribed?'},
    'sub_actions_sub': {
      'ru': 'Вставь ссылку из бота или привяжи Telegram — доступ подтянется сам.',
      'en': 'Paste the link from the bot or link Telegram — access loads automatically.'
    },
    'sub_actions_import': {'ru': 'Вставить ссылку', 'en': 'Paste link'},
    'sub_actions_link_tg': {'ru': 'Привязать Telegram', 'en': 'Link Telegram'},
    'acc_subscription': {'ru': 'Подписка (ссылка / импорт)', 'en': 'Subscription (link / import)'},
    'acc_subscription_d': {'ru': 'Добавить или обновить подписку в приложении', 'en': 'Add or update your subscription in the app'},
    'ip_auto': {'ru': 'Авто', 'en': 'Auto'},
    'lite_mode': {'ru': 'Режим экономии (слабые устройства)', 'en': 'Lite mode (weak devices)'},
    'compact_servers': {'ru': 'Компактный список серверов', 'en': 'Compact server list'},
    'compact_servers_d': {
      'ru': 'Два сервера в ряд — только флаг и пинг. Удобно, когда серверов много.',
      'en': 'Two servers per row — flag and ping only. Handy with many servers.'
    },
    'liquid_glass': {'ru': 'Liquid glass', 'en': 'Liquid glass'},
    'liquid_glass_d': {
      'ru': 'Эффект матового стекла на карточках. Можно отключить.',
      'en': 'Frosted-glass effect on cards. Can be turned off.'
    },
    'lite_mode_d': {
      'ru': 'Отключает падающие звёзды, вращение глобуса и тяжёлые анимации — приложение работает легче и быстрее.',
      'en': 'Disables shooting stars, globe rotation and heavy animations — the app runs lighter and faster.'
    },
    'net_good': {'ru': 'Отличный интернет', 'en': 'Great connection'},
    'net_ok': {'ru': 'Нормальный интернет', 'en': 'Decent connection'},
    'net_slow': {'ru': 'Медленный интернет', 'en': 'Slow connection'},
    // экраны раздела «Ещё»
    'st_title': {'ru': 'Тест скорости', 'en': 'Speed test'},
    'st_mbps': {'ru': 'Мбит/с', 'en': 'Mbps'},
    'st_avg': {'ru': 'Средняя', 'en': 'Average'},
    'st_run': {'ru': 'Начать тест', 'en': 'Start test'},
    'st_running': {'ru': 'Идёт тест…', 'en': 'Testing…'},
    'imp_title': {'ru': 'Импорт подписки', 'en': 'Import subscription'},
    'imp_hint2': {
      'ru': 'Вставь ссылку подписки из бота (начинается с https://) — или сам текст конфигов (vless://…, base64-подписку).',
      'en': 'Paste the subscription link from the bot (starts with https://) — or the config text itself (vless://…, base64 subscription).'
    },
    'imp_btn': {'ru': 'Импортировать', 'en': 'Import'},
    'imp_qr': {'ru': 'Добавить по QR-коду', 'en': 'Add by QR code'},
    'imp_paste': {'ru': 'Добавить из буфера', 'en': 'Paste from clipboard'},
    'imp_clip_empty': {'ru': 'Буфер обмена пуст', 'en': 'Clipboard is empty'},
    'imp_where': {
      'ru': 'Ещё нет подписки? Возьми её в нашем Telegram-боте:',
      'en': 'No subscription yet? Get one in our Telegram bot:'
    },
    'imp_get_in_bot': {'ru': 'Взять подписку в боте', 'en': 'Get subscription in the bot'},
    'imp_ok': {'ru': 'Импортировано серверов', 'en': 'Servers imported'},
    'sup_title': {'ru': 'Поддержка', 'en': 'Support'},
    'sup_hint': {'ru': 'Сообщение…', 'en': 'Message…'},
    'sup_empty': {
      'ru': 'Напиши нам прямо здесь — ответим в приложении.\nИли нажми значок Telegram вверху, чтобы написать в чат.',
      'en': 'Write to us right here — we\'ll reply in the app.\nOr tap the Telegram icon above to chat there.'
    },
    'sup_attach': {'ru': 'Прикрепить файл или фото', 'en': 'Attach a file or photo'},
    'logs_title2': {'ru': 'Логи', 'en': 'Logs'},
    'guide_title': {'ru': 'Как подключиться', 'en': 'How to connect'},
    // мультихоп
    'mh_routes_title': {'ru': 'Готовые маршруты (настоящий двойной хоп)', 'en': 'Ready routes (real double hop)'},
    'mh_connecting': {'ru': 'Подключаю двойной VPN', 'en': 'Connecting Double VPN'},
    'mh_or_single': {'ru': 'Или выбери страну выхода (одиночный туннель)', 'en': 'Or pick an exit country (single tunnel)'},
    'mh_dvpn': {'ru': 'Двойной VPN', 'en': 'Double VPN'},
    // QR
    'qr_added': {'ru': '✅ Подписка добавлена, серверов', 'en': '✅ Subscription added, servers'},
    'qr_fail': {'ru': 'Не удалось распознать подписку', 'en': 'Could not read the subscription'},
    'qr_title': {'ru': 'Добавить по QR', 'en': 'Add by QR'},
    'qr_hint': {'ru': 'Наведи камеру на QR-код подписки из нашего бота — подключение добавится автоматически.', 'en': 'Point the camera at the subscription QR from our bot — it will be added automatically.'},
    // серверы
    'srv_ping_all': {'ru': 'Пинговать все', 'en': 'Ping all'},
    'srv_none': {'ru': 'Нет серверов — импортируй подписку', 'en': 'No servers — import a subscription'},
    'srv_search': {'ru': 'Поиск страны или сервера', 'en': 'Search country or server'},
    'srv_sort': {'ru': 'Сортировка', 'en': 'Sort'},
    'srv_sort_ping': {'ru': 'Пинг', 'en': 'Ping'},
    'srv_sort_country': {'ru': 'Страна', 'en': 'Country'},
    'srv_sort_fav': {'ru': 'Избранное', 'en': 'Favorites'},
    // статистика
    'st_total_down': {'ru': 'Всего скачано', 'en': 'Total downloaded'},
    'st_total_up': {'ru': 'Всего отдано', 'en': 'Total uploaded'},
    'st_last7': {'ru': 'За последние 7 дней', 'en': 'Last 7 days'},
    'st_fav': {'ru': 'Любимые страны', 'en': 'Favorite countries'},
    'st_nodata': {'ru': 'Пока нет данных — подключись, и здесь появится статистика.', 'en': 'No data yet — connect and stats will appear here.'},
    'st_servers_n': {'ru': '{n} сервер(ов)', 'en': '{n} server(s)'},
    'st_country_total': {'ru': 'Всего по стране', 'en': 'Country total'},
    'st_by_server': {'ru': 'По серверам', 'en': 'By server'},
    'unit_b': {'ru': 'Б', 'en': 'B'},
    'unit_kb': {'ru': 'КБ', 'en': 'KB'},
    'unit_mb': {'ru': 'МБ', 'en': 'MB'},
    'unit_gb': {'ru': 'ГБ', 'en': 'GB'},
    // логи
    'clear': {'ru': 'Очистить', 'en': 'Clear'},
    'logs_empty': {'ru': 'Пока пусто — события появятся здесь', 'en': 'Empty — events will appear here'},
    'id_copied': {'ru': 'ID скопирован', 'en': 'ID copied'},
    // гайд подключения
    'guide_free_on': {
      'ru': 'Включаем бесплатный VPN для Telegram… Работать будет только Telegram.',
      'en': 'Enabling free VPN for Telegram… Only Telegram will work.'
    },
    'guide_free_connected': {
      'ru': 'VPN подключён! Работает только Telegram, остальное — без интернета до подписки.',
      'en': 'VPN connected! Only Telegram works; everything else has no internet until you subscribe.'
    },
    'guide_next': {'ru': 'Что дальше', 'en': "What's next"},
    'guide_s1_t': {'ru': 'Разреши VPN-профиль', 'en': 'Allow the VPN profile'},
    'guide_s1_b': {
      'ru': 'При первом включении система спросит разрешение на VPN — нажми «Разрешить». Это нужно, чтобы трафик шёл через туннель.',
      'en': 'On first launch the system asks for VPN permission — tap "Allow". This lets traffic go through the tunnel.'
    },
    'guide_s2_t': {'ru': 'Сейчас работает только Telegram', 'en': 'Only Telegram works for now'},
    'guide_s2_b': {
      'ru': 'В бесплатном режиме работает только Telegram — он идёт через VPN даже при блокировках. Остальные приложения и сайты пока без интернета: полный доступ откроется с подпиской.',
      'en': 'In free mode only Telegram works — it goes through the VPN even under blocks. Other apps and sites have no internet yet: full access comes with a subscription.'
    },
    'guide_sub_active': {
      'ru': 'Подписка активна! VPN работает для всех приложений — с авто-выбором лучшего сервера.',
      'en': 'Subscription active! The VPN works for all apps — with auto best-server selection.'
    },
    'guide_sub_s2_t': {'ru': 'Работает весь интернет', 'en': 'The whole internet works'},
    'guide_sub_s2_b': {
      'ru': 'Через VPN идут все приложения и сайты. Российские сервисы можно пускать напрямую в Настройках → Обход РФ.',
      'en': 'All apps and sites go through the VPN. Local services can bypass it in Settings → RU bypass.'
    },
    'guide_sub_s3_t': {'ru': 'Настрой под себя', 'en': 'Make it yours'},
    'guide_sub_s3_b': {
      'ru': 'В Настройках: авто-подключение, per-app правила, умный доступ к ИИ, свои серверы и многое другое.',
      'en': 'In Settings: auto-connect, per-app rules, smart AI access, your own servers and more.'
    },
    'guide_link_tg': {'ru': 'Привязать по Telegram ID', 'en': 'Link by Telegram ID'},
    'guide_s3_t': {'ru': 'Хочешь весь интернет?', 'en': 'Want the whole internet?'},
    'guide_s3_b': {
      'ru': 'Возьми подписку в нашем Telegram-боте и вставь ссылку — тогда VPN заработает для всех приложений с авто-выбором лучшего сервера.',
      'en': 'Get a subscription in our Telegram bot and paste the link — then the VPN works for all apps with auto-selection of the best server.'
    },
    'guide_open_bot': {'ru': 'Открыть бота и взять подписку', 'en': 'Open the bot and get a subscription'},
    'guide_have_link': {'ru': 'У меня есть ссылка подписки', 'en': 'I have a subscription link'},
    'guide_ok_home': {'ru': 'На главную', 'en': 'Go to home'},
    'splash_tagline': {'ru': 'Умный VPN с авто-роутингом', 'en': 'Smart VPN with auto-routing'},
    'wdg_connect': {'ru': 'Подключить', 'en': 'Connect'},
    'wdg_disconnect': {'ru': 'Отключить', 'en': 'Disconnect'},
    // экран «начало работы» (после онбординга / для новичка)
    'gs_tagline': {'ru': 'Премиум-VPN: быстрый, умный, без блокировок', 'en': 'Premium VPN: fast, smart, unblockable'},
    'gs_get_sub': {'ru': 'Получить подписку', 'en': 'Get subscription'},
    'gs_get_sub_d': {'ru': 'Полный VPN для всех приложений. Оформление за минуту в нашем Telegram-боте.', 'en': 'Full VPN for all apps. Set up in a minute in our Telegram bot.'},
    'gs_free': {'ru': 'Попробовать бесплатно', 'en': 'Try for free'},
    'gs_free_d': {'ru': 'VPN только для Telegram — работает сразу, без входа и оплаты.', 'en': 'VPN for Telegram only — works instantly, no login or payment.'},
    'gs_have_link': {'ru': 'У меня есть ссылка', 'en': 'I have a link'},
    'gs_have_link_d': {'ru': 'Вставь ссылку подписки из бота.', 'en': 'Paste the subscription link from the bot.'},
    'gs_no_tg': {'ru': 'Нет Telegram? Бот откроется в браузере — подписка придёт ссылкой.', 'en': 'No Telegram? The bot opens in a browser — the subscription arrives as a link.'},
    'gs_step': {'ru': 'Шаг {n}', 'en': 'Step {n}'},
    'gs_bot_manual': {'ru': 'Открой бота вручную: @variousvpnbot', 'en': 'Open the bot manually: @variousvpnbot'},
    // премиальная кнопка-CTA к боту после включения бесплатного режима
    'guide_get_full': {'ru': 'Получить полный VPN', 'en': 'Get the full VPN'},
    // авто-VPN в незнакомых сетях
    'awifi_nav': {'ru': 'Авто-VPN на чужом Wi-Fi', 'en': 'Auto-VPN on public Wi-Fi'},
    'awifi_nav_d': {'ru': 'Включать защиту в незнакомых сетях', 'en': 'Protect on unknown networks'},
    'awifi_title': {'ru': 'Авто-VPN на чужом Wi-Fi', 'en': 'Auto-VPN on public Wi-Fi'},
    'awifi_enable': {'ru': 'Включать VPN в незнакомых сетях', 'en': 'Turn on VPN in unknown networks'},
    'awifi_enable_d': {
      'ru': 'Как только подключаешься к Wi-Fi, которого нет в списке доверенных, — VPN поднимается сам. Дома и на работе (доверенные сети) не мешает.',
      'en': 'As soon as you join a Wi-Fi that is not in your trusted list, the VPN turns on by itself. At home or work (trusted networks) it stays out of the way.'
    },
    'awifi_trusted': {'ru': 'Доверенные сети', 'en': 'Trusted networks'},
    'awifi_trusted_d': {
      'ru': 'В этих Wi-Fi VPN не включается автоматически.',
      'en': 'The VPN will not auto-connect on these Wi-Fi networks.'
    },
    'awifi_add_current': {'ru': 'Добавить текущую сеть', 'en': 'Add current network'},
    'awifi_none': {'ru': 'Пока нет доверенных сетей', 'en': 'No trusted networks yet'},
    'awifi_no_ssid': {'ru': 'Не удалось определить Wi-Fi (нужен доступ к геолокации и активный Wi-Fi)', 'en': 'Could not detect Wi-Fi (needs location access and active Wi-Fi)'},
    'awifi_added': {'ru': 'Сеть добавлена в доверенные', 'en': 'Network added to trusted'},
    'awifi_perm': {'ru': 'Нужен доступ к геолокации — Android требует его, чтобы приложение видело имя Wi-Fi. Разреши в настройках.', 'en': 'Location access is required — Android needs it for the app to see the Wi-Fi name. Allow it in settings.'},
    'awifi_how_t': {'ru': 'Как это работает', 'en': 'How it works'},
    'awifi_how': {
      'ru': '• В незнакомой Wi-Fi (кафе, отель, аэропорт) VPN включается сам — именно там выше риск слежки и перехвата.\n• В доверенных сетях (дом, работа) VPN не навязывается — добавь их кнопкой ниже.\n\nЧто должно быть включено:\n• Доступ к геолокации для приложения — Android отдаёт имя Wi-Fi только с ним (само местоположение мы не используем и никуда не отправляем, это требование системы).\n• Включённая геолокация (GPS) в шторке — без неё система тоже скрывает имя сети.\n\nЕсли доступа или GPS нет — авто-режим просто не сработает, ничего не сломается.',
      'en': '• On an unknown Wi-Fi (café, hotel, airport) the VPN turns on by itself — that is exactly where snooping risk is highest.\n• On trusted networks (home, work) the VPN is not forced — add them with the button below.\n\nWhat must be enabled:\n• Location access for the app — Android only reveals the Wi-Fi name with it (we do not use or send your location anywhere; it is a system requirement).\n• Location (GPS) turned on in quick settings — without it the system also hides the network name.\n\nIf access or GPS is off, the auto mode simply won\'t trigger — nothing breaks.'
    },
    'streak_day_short': {'ru': 'дн', 'en': 'd'},
    'error': {'ru': 'Ошибка', 'en': 'Error'},
    'no_server': {'ru': 'Нет сервера', 'en': 'No server'},
    'free_tg': {'ru': 'Бесплатно · Telegram', 'en': 'Free · Telegram'},
    'free_tg_sub': {'ru': 'Только трафик Telegram', 'en': 'Telegram traffic only'},
    'free_rules_banner': {
      'ru': 'Бесплатный режим: VPN работает только для Telegram.',
      'en': 'Free mode: VPN works for Telegram only.'
    },
    'free_rules_locked': {
      'ru': 'Зафиксировано на Telegram (бесплатный режим)',
      'en': 'Locked to Telegram (free mode)'
    },
    'free_locked_title': {
      'ru': 'Нужна подписка',
      'en': 'Subscription required'
    },
    'free_locked_body': {
      'ru': 'В бесплатном режиме VPN работает только для Telegram. Чтобы настраивать правила для всех приложений и сайтов, оформи подписку в нашем боте.',
      'en': 'In free mode the VPN works for Telegram only. To set rules for all apps and sites, get a subscription in our bot.'
    },
    'free_locked_buy': {'ru': 'Купить подписку', 'en': 'Get subscription'},
    'free_connected': {'ru': 'Подключено · только Telegram', 'en': 'Connected · Telegram only'},
    'free_off': {'ru': 'Не подключено', 'en': 'Not connected'},
    'free_only_tg': {'ru': 'Только Telegram', 'en': 'Telegram only'},
    'free_server_label': {'ru': 'Сервер', 'en': 'Server'},
    'free_buy_full': {'ru': 'Открыть весь интернет — подписка', 'en': 'Unlock full internet — subscribe'},
    'free_auto_title': {'ru': 'Авто · Telegram', 'en': 'Auto · Telegram'},
    'free_auto_sub': {'ru': 'Сам подбирает рабочий сервер', 'en': 'Auto-picks a working server'},
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
    'autoconnect': {'ru': 'Автоподключение', 'en': 'Auto-connect'},
    'autoconnect_d': {
      'ru': 'Как только открываешь приложение — VPN сам подключается. Не нужно жать «Подключить».',
      'en': 'The moment you open the app, the VPN connects itself — no need to tap Connect.'
    },
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
    'days_short': {'ru': 'дн.', 'en': 'd'},
    'servers_label': {'ru': 'Серверов', 'en': 'Servers'},
    'unit_mbps': {'ru': 'МБ/с', 'en': 'MB/s'},
    'unit_kbps': {'ru': 'КБ/с', 'en': 'KB/s'},
    'link_tg': {'ru': 'Привязать Telegram', 'en': 'Link Telegram'},
    'link_tg_d': {'ru': 'Синхронизировать подписку и статус', 'en': 'Sync subscription and status'},
    'link_tg_hint': {
      'ru': 'Введи свой Telegram ID (узнать можно в нашем боте).',
      'en': 'Enter your Telegram ID (get it from our bot).'
    },
    'link_tg_openbot': {'ru': 'Открыть бота (узнать ID)', 'en': 'Open bot (find ID)'},
    'cancel': {'ru': 'Отмена', 'en': 'Cancel'},
    'save': {'ru': 'Сохранить', 'en': 'Save'},
    'delete': {'ru': 'Удалить', 'en': 'Delete'},
    'srv_rename': {'ru': 'Переименовать сервер', 'en': 'Rename server'},
    'srv_delete_q': {'ru': 'Удалить сервер?', 'en': 'Delete server?'},
    'srv_move_folder': {'ru': 'В папку', 'en': 'Move to folder'},
    'folder_all': {'ru': 'Все серверы', 'en': 'All servers'},
    'folder_add': {'ru': 'Папка', 'en': 'Folder'},
    'folder_new': {'ru': 'Новая папка', 'en': 'New folder'},
    'folder_hint': {'ru': 'Напр. WiFi, Мобильный', 'en': 'e.g. WiFi, Mobile'},
    'folder_delete_q': {'ru': 'Удалить папку?', 'en': 'Delete folder?'},
    'folder_none': {'ru': 'Без папки', 'en': 'No folder'},
    'folder_add_servers': {'ru': 'Добавить серверы', 'en': 'Add servers'},
    'folder_pick_servers': {'ru': 'Серверы в папке', 'en': 'Servers in folder'},
    'folder_empty': {
      'ru': 'В этой папке пока нет серверов',
      'en': 'No servers in this folder yet'
    },
    'paste': {'ru': 'Вставить', 'en': 'Paste'},

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
      'ru': 'Эти сайты будут открываться напрямую, минуя VPN.',
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
    'autorefresh': {'ru': 'Авто-обновление подписки', 'en': 'Auto-update subscription'},
    'autorefresh_d': {
      'ru': 'Периодически заново скачивать список серверов из подписки.',
      'en': 'Periodically re-download the server list from your subscription.'
    },
    'autorefresh_every': {'ru': 'Обновлять каждые', 'en': 'Update every'},
    'ondemand': {'ru': 'On Demand', 'en': 'On Demand'},
    'ondemand_d': {
      'ru': 'Сам VPN не включает. Но если во время работы связь оборвётся — молча поднимет туннель заново, чтобы ты не остался в сети без VPN.',
      'en': 'Does not turn the VPN on by itself. But if the connection drops while you are online, it silently brings the tunnel back so you are never left online without VPN.'
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
    'mh_privacy_title': {'ru': 'Двойной хоп', 'en': 'Double hop'},
    'mh_privacy_body': {
      'ru': 'Выбери готовый маршрут ниже — трафик реально пройдёт через ДВЕ страны (вход → выход). Даже если выходной сервер захотят вычислить, увидят только IP входного, а не твой. Ниже можно выбрать и одиночный выход.',
      'en': 'Pick a ready route below — traffic really goes through TWO countries (entry → exit). Even if the exit server is compromised, only the entry\'s IP is seen, not yours. You can also pick a single exit below.'
    },
    'mh_speed': {
      'ru': 'Выбирай выход по стране, которая нужна сайтам и сервисам. Чем дальше сервер — тем выше пинг.',
      'en': 'Pick the exit by the country you need for sites and services. The farther the server, the higher the ping.'
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
      'ru': 'Добавь до 5 своих серверов. Вставь share-ссылку (vless://…), их список, ИЛИ целиком Xray-конфиг {"outbounds":[…]} — приложение само вытащит сервер. Появятся рядом с нашими.',
      'en': 'Add up to 5 of your own servers. Paste a share link (vless://…), a list of them, OR a full Xray config {"outbounds":[…]} — the app extracts the server. They appear next to ours.'
    },
    'cs_locked': {'ru': 'Твоя подписка Various VPN неактивна — оформи её, и добавление своих серверов откроется.', 'en': 'Your Various VPN subscription is inactive — get one to unlock adding your own servers.'},
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
