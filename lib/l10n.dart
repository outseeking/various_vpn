/// Простая локализация RU/EN. `L.current` — текущий язык (ставит AppState).
/// `L.t('key')` возвращает строку. Экраны, читающие AppState через watch,
/// перестраиваются при смене языка.
library;

import 'package:flutter/foundation.dart';

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

  /// Дата словами на языке интерфейса: «14 августа 2026» / «August 14, 2026».
  /// Живёт здесь, а не в экране: дату показывают в нескольких местах, и
  /// выглядеть везде она обязана одинаково.
  static String date(DateTime d) {
    const ru = [
      '',
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря'
    ];
    const en = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return current == 'en'
        ? '${en[d.month]} ${d.day}, ${d.year}'
        : '${d.day} ${ru[d.month]} ${d.year}';
  }

  /// Русское склонение существительного по числу (1 день / 2 дня / 5 дней).
  /// EN: единственное при n==1, иначе множественное.
  static String plural(int n,
      {required String one,
      required String few,
      required String many,
      String? enOne,
      String? enMany}) {
    if (current == 'en') return n == 1 ? (enOne ?? one) : (enMany ?? many);
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 >= 11 && mod100 <= 14) return many;
    if (mod10 == 1) return one;
    if (mod10 >= 2 && mod10 <= 4) return few;
    return many;
  }

  /// Слово «день» в правильной форме для числа [n] (день/дня/дней · day/days).
  static String days(int n) => plural(n,
      one: 'день', few: 'дня', many: 'дней', enOne: 'day', enMany: 'days');

  /// Весь словарь целиком — для проверок в тестах.
  ///
  /// Открыто наружу намеренно: полнота перевода проверяется автоматически, а
  /// не глазами. Пропущенный английский вариант иначе всплывает уже у
  /// пользователя.
  @visibleForTesting
  static Map<String, Map<String, String>> get debugAll => _d;

  static const Map<String, Map<String, String>> _d = {
    // --- онбординг ---
    'skip': {'ru': 'Пропустить', 'en': 'Skip'},
    'next': {'ru': 'Далее', 'en': 'Next'},
    // Последний слайд онбординга обещает конкретную выгоду, а не «Начать».
    'ob_cta': {'ru': 'Забрать 3 дня', 'en': 'Claim 3 free days'},
    // --- единый блок подключения (ConnectWays) ---
    'cw_clip': {'ru': 'Войти как {id}', 'en': 'Sign in as {id}'},
    'cw_or': {'ru': 'или', 'en': 'or'},
    // Снятие возражений под главной кнопкой — только честные обещания.
    'gs_risk_card': {'ru': 'Без карты', 'en': 'No card'},
    'gs_risk_auto': {'ru': 'Без автосписаний', 'en': 'No auto-charges'},
    'gs_risk_min': {'ru': 'Настройка — минута', 'en': 'Set up in a minute'},
    'no_net_btn': {'ru': 'Нет интернета', 'en': 'No internet'},
    // --- продление подписки (самая дешёвая конверсия) ---
    'renew_cta': {'ru': 'Продлить подписку', 'en': 'Renew subscription'},
    'renew_soon': {
      'ru': 'Осталось {n} {d}. Продлишь сейчас — не отключим.',
      'en': 'Only {n} {d} left. Renew now and stay connected.'
    },
    'renew_today': {
      'ru': 'Заканчивается сегодня. Продли, чтобы не потерять доступ.',
      'en': 'Expires today. Renew so you don\'t lose access.'
    },
    'renew_over': {
      'ru':
          'Подписка закончилась. Серия и настройки сохранены — продли и всё вернётся.',
      'en':
          'Your subscription ended. Streak and settings are saved — renew and it all comes back.'
    },
    'guide_later': {'ru': 'Позже, на главную', 'en': 'Later, go home'},

    // --- главный экран ---
    'protected': {'ru': 'Подключено', 'en': 'Connected'},
    'disconnected': {'ru': 'Отключено', 'en': 'Disconnected'},
    'connecting': {'ru': 'Подключение…', 'en': 'Connecting…'},
    'ai_auto': {'ru': 'Авто', 'en': 'Auto'},
    'manual': {'ru': 'Ручной', 'en': 'Manual'},
    'mode_hint_ai': {
      'ru': 'Приложение само выберет самый быстрый сервер',
      'en': 'The app picks the fastest server for you'
    },
    'mode_hint_manual': {
      'ru': 'Выбери сервер вручную — тапни по стране ниже',
      'en': 'Pick a server manually — tap a country below'
    },
    'ping': {'ru': 'пинг', 'en': 'ping'},
    'servers': {'ru': 'Серверы', 'en': 'Servers'},
    'ping_btn': {'ru': 'Пинг', 'en': 'Ping'},
    'update_short': {'ru': 'Обновить', 'en': 'Update'},
    'sub_actions_title': {
      'ru': 'Уже есть подписка?',
      'en': 'Already subscribed?'
    },
    'sub_actions_sub': {
      'ru':
          'Вставь ссылку из бота или привяжи Telegram — доступ подтянется сам.',
      'en':
          'Paste the link from the bot or link Telegram — access loads automatically.'
    },
    'ip_auto': {'ru': 'Авто', 'en': 'Auto'},
    'lite_mode': {
      'ru': 'Режим экономии (слабые устройства)',
      'en': 'Lite mode (weak devices)'
    },
    'lite_mode_d': {
      'ru': 'Меньше эффектов — дольше держит батарея',
      'en': 'Fewer effects — longer battery life'
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
      'ru':
          'Подойдёт ID из бота, ссылка на подписку или сами настройки серверов. Можно добавить и подписку другого сервиса — приложение будет работать с её серверами.',
      'en':
          'An ID from the bot, a subscription link or the configs themselves all work. You can also add another service\'s subscription — the app will use its servers.'
    },
    'imp_field_hint': {
      'ru': 'ID, ссылка или vless://…',
      'en': 'ID, link or vless://…'
    },
    'imp_fail': {'ru': 'Не удалось добавить', 'en': 'Could not add'},
    'imp_btn': {'ru': 'Импортировать', 'en': 'Import'},
    'imp_qr': {'ru': 'Добавить по QR-коду', 'en': 'Add by QR code'},
    'imp_paste': {'ru': 'Добавить из буфера', 'en': 'Paste from clipboard'},
    'imp_clip_empty': {'ru': 'Буфер обмена пуст', 'en': 'Clipboard is empty'},
    'imp_where': {
      'ru': 'Ещё нет подписки? Возьми её в нашем Telegram-боте:',
      'en': 'No subscription yet? Get one in our Telegram bot:'
    },
    'imp_get_in_bot': {
      'ru': 'Взять подписку в боте',
      'en': 'Get subscription in the bot'
    },
    'imp_ok': {'ru': 'Импортировано серверов', 'en': 'Servers imported'},
    'sup_title': {'ru': 'Поддержка', 'en': 'Support'},
    'sup_hint': {'ru': 'Сообщение…', 'en': 'Message…'},
    'sup_attach': {
      'ru': 'Прикрепить файл или фото',
      'en': 'Attach a file or photo'
    },
    'logs_title2': {'ru': 'Логи', 'en': 'Logs'},
    'guide_title': {'ru': 'Как подключиться', 'en': 'How to connect'},
    // баннер «нет интернета»
    // --- экран входа: приоритет входу по ID ---
    'gs_id_title': {
      'ru': 'Уже есть подписка? Войди по ID',
      'en': 'Already subscribed? Sign in with ID'
    },
    'gs_id_hint': {
      'ru': 'ID из бота',
      'en': 'ID from the bot — e.g. 1658245753'
    },
    'gs_id_help': {
      'ru': 'ID показан в боте под приветствием.',
      'en': 'Your ID is shown in the bot under the greeting.'
    },
    'gs_id_go': {'ru': 'Войти', 'en': 'Sign in'},
    'gs_id_paste': {'ru': 'Вставить', 'en': 'Paste'},
    'gs_id_empty': {
      'ru': 'Введи свой ID из бота',
      'en': 'Enter your ID from the bot'
    },
    'gs_from_price': {'ru': 'от {p} ₽', 'en': 'from {p} ₽'},
    // текст постоянного уведомления VPN в бесплатном режиме
    'notif_free': {
      'ru': '🆓 Бесплатный режим · работает только Telegram',
      'en': '🆓 Free mode · Telegram only'
    },
    'gs_plans': {'ru': 'Тарифы и оплата', 'en': 'Plans & payment'},
    'gs_trial_d': {
      'ru': 'Без карты, за минуту',
      'en': 'No card, takes a minute'
    },
    'gs_way_link': {'ru': 'По ссылке', 'en': 'By link'},
    'gs_way_qr': {'ru': 'По QR-коду', 'en': 'By QR code'},
    'wdg_no_server': {'ru': 'Сервер не выбран', 'en': 'No server selected'},
    'wdg_auto_tg': {'ru': 'Авто · Telegram', 'en': 'Auto · Telegram'},
    'no_net_title': {
      'ru': 'Нет подключения к интернету',
      'en': 'No internet connection'
    },
    'no_net_body': {
      'ru':
          'VPN не заработает без сети. Включи Wi-Fi или мобильный интернет — и возвращайся.',
      'en':
          'VPN won\'t work without a network. Turn on Wi-Fi or mobile data and come back.'
    },
    // мультихоп
    // QR
    'qr_added': {
      'ru': '✅ Подписка добавлена, серверов',
      'en': '✅ Subscription added, servers'
    },
    'qr_fail': {
      'ru': 'Не удалось распознать подписку',
      'en': 'Could not read the subscription'
    },
    'qr_title': {'ru': 'Добавить по QR', 'en': 'Add by QR'},
    'qr_hint': {
      'ru':
          'Наведи камеру на QR-код подписки из нашего бота — подключение добавится автоматически.',
      'en':
          'Point the camera at the subscription QR from our bot — it will be added automatically.'
    },
    // серверы
    'srv_ping_all': {'ru': 'Пинговать все', 'en': 'Ping all'},
    'srv_none': {
      'ru': 'Нет серверов — импортируй подписку',
      'en': 'No servers — import a subscription'
    },
    'srv_search': {
      'ru': 'Поиск страны или сервера',
      'en': 'Search country or server'
    },
    // статистика
    'st_total_down': {'ru': 'Всего скачано', 'en': 'Total downloaded'},
    'st_total_up': {'ru': 'Всего отдано', 'en': 'Total uploaded'},
    'st_last7': {'ru': 'За последние 7 дней', 'en': 'Last 7 days'},
    'st_fav': {'ru': 'Любимые страны', 'en': 'Favorite countries'},
    'st_nodata': {
      'ru': 'Пока нет данных — подключись, и здесь появится статистика.',
      'en': 'No data yet — connect and stats will appear here.'
    },
    'st_servers_n': {'ru': '{n} сервер(ов)', 'en': '{n} server(s)'},
    'st_country_total': {'ru': 'Всего по стране', 'en': 'Country total'},
    'st_by_server': {'ru': 'По серверам', 'en': 'By server'},
    'unit_b': {'ru': 'Б', 'en': 'B'},
    'unit_kb': {'ru': 'КБ', 'en': 'KB'},
    'unit_mb': {'ru': 'МБ', 'en': 'MB'},
    'unit_gb': {'ru': 'ГБ', 'en': 'GB'},
    // логи
    'clear': {'ru': 'Очистить', 'en': 'Clear'},
    'logs_empty': {
      'ru': 'Пока пусто — события появятся здесь',
      'en': 'Empty — events will appear here'
    },
    // гайд подключения
    'guide_free_on': {
      'ru': 'Включаем бесплатный VPN для Telegram…',
      'en': 'Enabling free VPN for Telegram…'
    },
    'guide_free_connected': {
      'ru':
          'VPN подключён! Работает только Telegram, остальное — без интернета до подписки.',
      'en':
          'VPN connected! Only Telegram works; everything else has no internet until you subscribe.'
    },
    'guide_next': {'ru': 'Что дальше', 'en': "What's next"},
    'guide_s1_t': {'ru': 'Разреши VPN-профиль', 'en': 'Allow the VPN profile'},
    'guide_s1_b': {
      'ru': 'Нажми «ОК» в окне запроса — без этого VPN не запустится',
      'en': 'Tap OK in the request dialog — the VPN cannot start without it'
    },
    'guide_s2_t': {
      'ru': 'Сейчас работает только Telegram',
      'en': 'Only Telegram works for now'
    },
    'guide_s2_b': {
      'ru': 'Telegram работает через VPN бесплатно и без ограничений по времени',
      'en': 'Telegram works through the VPN free, with no time limit'
    },
    'guide_sub_active': {
      'ru':
          'Подписка активна! VPN работает для всех приложений — с авто-выбором лучшего сервера.',
      'en':
          'Subscription active! The VPN works for all apps — with auto best-server selection.'
    },
    'guide_sub_s2_t': {
      'ru': 'Работает весь интернет',
      'en': 'The whole internet works'
    },
    'guide_sub_s2_b': {
      'ru':
          'Через VPN идут все приложения и сайты. Российские сервисы можно пускать напрямую в Настройках → Обход РФ.',
      'en':
          'All apps and sites go through the VPN. Local services can bypass it in Settings → RU bypass.'
    },
    'guide_sub_s3_t': {'ru': 'Настрой под себя', 'en': 'Make it yours'},
    'guide_sub_s3_b': {
      'ru':
          'В Настройках: авто-подключение, per-app правила, умный доступ к ИИ, свои серверы и многое другое.',
      'en':
          'In Settings: auto-connect, per-app rules, smart AI access, your own servers and more.'
    },
    'guide_s3_t': {
      'ru': 'Открой всё остальное',
      'en': 'Open everything else'
    },
    'guide_s3_b': {
      'ru': 'Подписка в боте — без карты, за минуту. Весь интернет откроется сразу',
      'en': 'Subscribe in the bot — no card, takes a minute. The whole internet opens at once'
    },
    'guide_open_bot': {
      'ru': 'Открыть бота и забрать 3 дня',
      'en': 'Open the bot and grab 3 days'
    },
    'guide_ok_home': {'ru': 'На главную', 'en': 'Go to home'},
    'splash_tagline': {
      'ru': 'Быстрый VPN, который просто работает',
      'en': 'A fast VPN that just works'
    },
    'wdg_connect': {'ru': 'Подключить', 'en': 'Connect'},
    'wdg_disconnect': {'ru': 'Отключить', 'en': 'Disconnect'},
    // экран «начало работы» (после онбординга / для новичка)
    'gs_tagline': {
      'ru': 'Быстрый VPN без блокировок — сайты и приложения снова работают',
      'en': 'A fast VPN without blocks — your sites and apps work again'
    },
    'gs_badge_ru': {'ru': 'Сервер подбирается сам', 'en': 'Server picked for you'},
    'gs_badge_dev': {'ru': 'До 3 устройств', 'en': 'Up to 3 devices'},
    'gs_badge_nolog': {'ru': 'Без логов', 'en': 'No logs'},
    'gs_get_sub': {
      'ru': 'Попробовать 3 дня бесплатно',
      'en': 'Try 3 days free'
    },
    // премиальная кнопка-CTA к боту после включения бесплатного режима
    // авто-VPN в незнакомых сетях
    'awifi_title': {
      'ru': 'Авто-VPN на чужом Wi-Fi',
      'en': 'Auto-VPN on public Wi-Fi'
    },
    'awifi_enable': {
      'ru': 'Включать VPN в незнакомых сетях',
      'en': 'Turn on VPN in unknown networks'
    },
    'awifi_enable_d': {
      'ru':
          'Как только подключаешься к Wi-Fi, которого нет в списке доверенных, — VPN поднимается сам. Дома и на работе (доверенные сети) не мешает.',
      'en':
          'As soon as you join a Wi-Fi that is not in your trusted list, the VPN turns on by itself. At home or work (trusted networks) it stays out of the way.'
    },
    'awifi_trusted': {'ru': 'Доверенные сети', 'en': 'Trusted networks'},
    'awifi_trusted_d': {
      'ru': 'В этих Wi-Fi VPN не включается автоматически.',
      'en': 'The VPN will not auto-connect on these Wi-Fi networks.'
    },
    'awifi_add_current': {
      'ru': 'Добавить текущую сеть',
      'en': 'Add current network'
    },
    'awifi_none': {
      'ru': 'Пока нет доверенных сетей',
      'en': 'No trusted networks yet'
    },
    'awifi_no_ssid': {
      'ru':
          'Не удалось определить Wi-Fi (нужен доступ к геолокации и активный Wi-Fi)',
      'en': 'Could not detect Wi-Fi (needs location access and active Wi-Fi)'
    },
    'awifi_perm': {
      'ru':
          'Нужен доступ к геолокации — Android требует его, чтобы приложение видело имя Wi-Fi. Разреши в настройках.',
      'en':
          'Location access is required — Android needs it for the app to see the Wi-Fi name. Allow it in settings.'
    },
    'awifi_how_t': {'ru': 'Как это работает', 'en': 'How it works'},
    'awifi_how': {
      'ru':
          '• В незнакомой Wi-Fi (кафе, отель, аэропорт) VPN включается сам — именно там выше риск слежки и перехвата.\n• В доверенных сетях (дом, работа) VPN не навязывается — добавь их кнопкой ниже.\n\nЧто должно быть включено:\n• Доступ к геолокации для приложения — Android отдаёт имя Wi-Fi только с ним (само местоположение мы не используем и никуда не отправляем, это требование системы).\n• Включённая геолокация (GPS) в шторке — без неё система тоже скрывает имя сети.\n\nЕсли доступа или GPS нет — авто-режим просто не сработает, ничего не сломается.',
      'en':
          '• On an unknown Wi-Fi (café, hotel, airport) the VPN turns on by itself — that is exactly where snooping risk is highest.\n• On trusted networks (home, work) the VPN is not forced — add them with the button below.\n\nWhat must be enabled:\n• Location access for the app — Android only reveals the Wi-Fi name with it (we do not use or send your location anywhere; it is a system requirement).\n• Location (GPS) turned on in quick settings — without it the system also hides the network name.\n\nIf access or GPS is off, the auto mode simply won\'t trigger — nothing breaks.'
    },
    'streak_day_short': {'ru': 'дн', 'en': 'd'},
    'error': {'ru': 'Ошибка', 'en': 'Error'},
    'no_server': {'ru': 'Нет сервера', 'en': 'No server'},
    'free_tg': {'ru': 'Бесплатно · Telegram', 'en': 'Free · Telegram'},
    'free_tg_sub': {
      'ru': 'Только трафик Telegram',
      'en': 'Telegram traffic only'
    },
    'free_rules_banner': {
      'ru': 'Бесплатный режим: VPN работает только для Telegram.',
      'en': 'Free mode: VPN works for Telegram only.'
    },
    'free_rules_locked': {
      'ru': 'Зафиксировано на Telegram (бесплатный режим)',
      'en': 'Locked to Telegram (free mode)'
    },
    'free_locked_buy': {'ru': 'Купить подписку', 'en': 'Get subscription'},
    'free_connected': {
      'ru': 'Подключено · только Telegram',
      'en': 'Connected · Telegram only'
    },
    'free_off': {'ru': 'Не подключено', 'en': 'Not connected'},
    'free_only_tg': {'ru': 'Только Telegram', 'en': 'Telegram only'},
    'free_server_label': {'ru': 'Сервер', 'en': 'Server'},
    'free_buy_full': {
      'ru': 'Хочу полный доступ →',
      'en': 'I want full access →'
    },
    'act_title': {'ru': 'Включить полный доступ', 'en': 'Get full access'},
    'act_sub': {
      'ru': 'Все сайты и приложения на скорости. Выбери, как подключить:',
      'en': 'All sites and apps at full speed. Pick how to connect:'
    },
    'act_get_bot': {'ru': 'Оформить подписку', 'en': 'Get a subscription'},
    'act_get_bot_d': {
      'ru': 'Быстро и просто в нашем Telegram-боте',
      'en': 'Fast and easy in our Telegram bot'
    },
    'free_auto_title': {'ru': 'Авто · Telegram', 'en': 'Auto · Telegram'},
    'free_auto_sub': {
      'ru': 'Сам подбирает рабочий сервер',
      'en': 'Auto-picks a working server'
    },
    'import_hint': {'ru': 'Импортируй подписку', 'en': 'Import subscription'},
    'traffic_via': {
      'ru': 'Трафик идёт через VPN',
      'en': 'Traffic goes via VPN'
    },

    // --- сессия ---
    'time': {'ru': 'Время', 'en': 'Time'},
    'downloaded': {'ru': 'Скачано', 'en': 'Downloaded'},
    'uploaded': {'ru': 'Отдано', 'en': 'Uploaded'},

    // --- настройки ---
    'settings': {'ru': 'Настройки', 'en': 'Settings'},
    'sec_account': {'ru': 'Аккаунт', 'en': 'Account'},
    'sec_connection': {'ru': 'Подключение', 'en': 'Connection'},
    // --- новая структура настроек (два уровня) ---
    'sec_vpn': {'ru': 'Настройки VPN', 'en': 'VPN settings'},
    'sec_connection_d': {
      'ru': 'Когда включаться, что делать при обрыве',
      'en': 'When to connect, what to do on drop'
    },
    'sec_tunnel': {'ru': 'Туннель', 'en': 'Tunnel'},
    'sec_tunnel_d': {
      'ru': 'Что идёт через VPN, а что напрямую',
      'en': 'What goes through the VPN and what doesn\'t'
    },
    'sec_tools': {'ru': 'Инструменты', 'en': 'Tools'},
    'sec_help': {'ru': 'Помощь', 'en': 'Help'},
    'conn_grp_start': {'ru': 'Включение', 'en': 'Turning on'},
    'conn_grp_safety': {'ru': 'Защита', 'en': 'Protection'},
    'tun_grp_routing': {'ru': 'Маршруты', 'en': 'Routing'},
    'tun_grp_net': {'ru': 'Сеть', 'en': 'Network'},
    'tun_grp_speed': {'ru': 'Скорость и доступ', 'en': 'Speed & access'},
    'mux': {'ru': 'Ускорение загрузки', 'en': 'Faster page loads'},
    'mux_d': {
      'ru': 'Сайты открываются быстрее. Для больших загрузок лучше выключить',
      'en': 'Pages open faster. Better off for large downloads'
    },
    'lan_direct': {
      'ru': 'Домашняя сеть напрямую',
      'en': 'Local network direct'
    },
    'lan_direct_d': {
      'ru': 'Принтер, телевизор и роутер остаются доступны',
      'en': 'Printer, TV and router stay reachable'
    },
    'tun_grp_own': {'ru': 'Свои серверы', 'en': 'Your own servers'},
    'ping_label_d': {
      'ru': 'Как замеряем скорость отклика серверов',
      'en': 'How we measure server response'
    },
    'logs_d': {
      'ru': 'Что и через какой сервер идёт прямо сейчас',
      'en': 'What goes through which server right now'
    },
    // --- мои подписки ---
    'subs_title': {'ru': 'Мои подписки', 'en': 'My subscriptions'},
    'subs_owner': {'ru': 'Оформлена на', 'en': 'Registered to'},
    'subs_until_label': {'ru': 'Действует до', 'en': 'Valid until'},
    'subs_ours': {'ru': 'Various VPN', 'en': 'Various VPN'},
    'subs_none': {'ru': 'Подписки нет', 'en': 'No subscription'},
    'subs_own_active': {'ru': 'Своя подписка', 'en': 'Your own subscription'},
    'subs_ours_off': {
      'ru':
          'Наши серверы закрыты. Оформи подписку — откроются все страны и настройки.',
      'en':
          'Our servers are locked. Get a subscription to unlock every country and setting.'
    },
    'subs_foreign': {'ru': 'Подписки других сервисов', 'en': 'Other services'},
    'subs_servers': {'ru': '{n} серверов', 'en': '{n} servers'},
    'subs_tap_remove': {
      'ru': 'Нажми на подписку, чтобы убрать её.',
      'en': 'Tap a subscription to remove it.'
    },
    'subs_refresh': {'ru': 'Обновить серверы', 'en': 'Refresh servers'},
    'nosub_title': {
      'ru': 'Нужна подписка',
      'en': 'Subscription needed'
    },
    'nosub_body': {
      'ru': 'Этот ID мы знаем, но активной подписки на нём нет. '
          'Оформи или продли её в боте — доступ откроется сразу, '
          'вводить ID заново не придётся.',
      'en': 'We know this ID, but it has no active subscription. Get or '
          'renew it in the bot — access opens right away, no need to '
          'enter the ID again.'
    },
    'nosub_cta': {
      'ru': 'Тарифы и оплата',
      'en': 'Plans and payment'
    },
    'later': {'ru': 'Позже', 'en': 'Later'},
    'id_no_sub': {
      'ru': 'По этому ID подписка не найдена или закончилась. Проверь ID — он '
          'показан в боте — или оформи подписку.',
      'en': 'No active subscription for this ID. Check the ID shown in the bot, '
          'or get a subscription.'
    },
    'id_no_server': {
      'ru': 'Наш сервер сейчас не отвечает — проверить подписку не удалось. '
          'Это не значит, что с ней что-то не так. Попробуй через несколько '
          'минут или добавь подписку ссылкой.',
      'en': 'Our server is not responding, so we could not check the '
          'subscription. That does not mean anything is wrong with it. Try '
          'again in a few minutes or add the subscription by link.'
    },
    'refresh_nothing': {
      'ru': 'Обновлять нечего: подписка не добавлена',
      'en': 'Nothing to refresh: no subscription added'
    },
    'refresh_ok': {
      'ru': 'Обновлено. Серверов: {n}',
      'en': 'Updated. Servers: {n}'
    },
    'refresh_fail': {
      'ru': 'Не удалось обновить: сервис не ответил',
      'en': 'Could not update: the service did not respond'
    },
    'refresh_fail_vpn': {
      'ru': 'Не удалось обновить: запрос идёт через включённый VPN. Выключи '
          'подключение и попробуй снова.',
      'en': 'Could not update: the request goes through the active VPN. '
          'Disconnect and try again.'
    },
    'subs_refresh_ok': {
      'ru': 'Обновлено. Серверов: {n}',
      'en': 'Updated. Servers: {n}'
    },
    'subs_refresh_fail': {
      'ru': 'Не удалось обновить: сервис не ответил. Если включён VPN — '
          'выключи его и попробуй ещё раз.',
      'en': 'Could not update: the service did not respond. If the VPN is on, '
          'turn it off and try again.'
    },
    'subs_add': {'ru': 'Добавить подписку', 'en': 'Add a subscription'},
    'srv_own': {'ru': 'СВОЙ', 'en': 'OWN'},
    'ping_every': {
      'ru': 'Как часто перемерять пинг — для режима «Авто»',
      'en': 'How often to re-measure ping — for Auto mode'
    },
    'ping_every_off': {'ru': 'Не мерить', 'en': 'Off'},
    // Прямо говорим, на что влияет настройка: без этого человек видел набор
    // интервалов и не понимал, зачем они и почему что-то должно мериться само.
    'ping_every_hint': {
      'ru': 'Нужно только режиму «Авто»: по этим числам он выбирает сервер.\n'
          'Реже — меньше расход батареи',
      'en': 'Only the Auto mode needs this: it picks a server by these numbers.\n'
          'Less often means less battery'
    },
    'unit_sec': {'ru': 'сек', 'en': 'sec'},
    'unit_min': {'ru': 'мин', 'en': 'min'},
    'srv_dead': {
      'ru': 'Не отвечает — трафик не идёт',
      'en': 'Not responding — no traffic'
    },
    // --- шторка «нужна подписка» ---
    'pw_title': {'ru': 'Нужна подписка', 'en': 'Subscription needed'},
    'pw_perk_countries': {
      'ru': 'Все страны и серверы, а не только Telegram',
      'en': 'Every country and server, not just Telegram'
    },
    'pw_perk_speed': {
      'ru': 'Полная скорость без ограничений трафика',
      'en': 'Full speed, no traffic limits'
    },
    'pw_perk_devices': {
      'ru': 'Три устройства на одну подписку',
      'en': 'Three devices on one subscription'
    },
    'pw_perk_settings': {
      'ru': 'Тонкие настройки: маршруты, приложения, блокировки',
      'en': 'Fine control: routing, per-app rules, blocking'
    },
    'pw_cta': {'ru': 'Забрать 3 дня бесплатно', 'en': 'Claim 3 free days'},
    'pw_no_card': {
      'ru': 'Без карты и без автосписаний',
      'en': 'No card, no auto-charges'
    },
    'pw_have_sub': {
      'ru': 'Подписка уже есть — войти',
      'en': 'Already subscribed — sign in'
    },
    'pw_unlocked': {'ru': 'Доступ открыт', 'en': 'Access unlocked'},
    // --- иконка приложения ---
    'app_icon': {'ru': 'Иконка приложения', 'en': 'App icon'},
    'app_icon_d': {
      'ru': 'Шесть вариантов',
      'en': 'Six looks'
    },
    'icon_intro': {
      'ru': 'Знак остаётся нашим — меняется оправа. Выбери тот, что лучше садится на твой домашний экран.',
      'en': 'The mark stays ours — only the frame changes. Pick the one that sits best on your home screen.'
    },
    'icon_note': {
      'ru': 'Иконка сменится, когда закроешь приложение',
      'en': 'The icon changes once you leave the app'
    },
    'icon_changed': {
      'ru': 'Готово',
      'en': 'Done'
    },
    'icon_failed': {
      'ru': 'Не удалось сменить иконку',
      'en': 'Could not change the icon'
    },
    'icon_classic': {'ru': 'Классика', 'en': 'Classic'},
    'icon_midnight': {'ru': 'Полночь', 'en': 'Midnight'},
    'icon_indigo': {'ru': 'Индиго', 'en': 'Indigo'},
    'icon_steel': {'ru': 'Графит', 'en': 'Graphite'},
    'icon_pearl': {'ru': 'Перламутр', 'en': 'Pearl'},
    'icon_lime': {'ru': 'Лайм', 'en': 'Lime'},
    // --- почему не добавилась чужая подписка ---
    'fsub_vpn_on': {
      'ru': 'Сейчас включён VPN — запрос идёт через него. Выключи подключение и попробуй ещё раз.',
      'en': 'The VPN is on, so the request goes through it. Disconnect and try again.'
    },
    'fsub_bad_url': {
      'ru': 'Это не похоже на ссылку. Она должна начинаться с https://',
      'en': 'That does not look like a link. It should start with https://'
    },
    'fsub_no_host': {
      'ru': 'Сервер по этой ссылке не отвечает. Проверь адрес — или интернет, если сейчас включён VPN.',
      'en': 'No response from that address. Check the link — or your internet if the VPN is on right now.'
    },
    'fsub_tls': {
      'ru': 'У сервера просроченный сертификат — соединение небезопасно. Возьми свежую ссылку у своего сервиса.',
      'en': 'That server has an expired certificate, so the connection is not safe. Get a fresh link from your provider.'
    },
    'fsub_refused': {
      'ru': 'Сервис не отдаёт подписку этому приложению. Обычно это лимит '
          'устройств: отключи лишнее в его боте и попробуй снова.',
      'en': 'The service refuses to give the subscription to this app. Usually '
          'a device limit: disconnect a device in its bot and try again.'
    },
    'fsub_not_found': {
      'ru': 'Подписка не найдена (404). Скорее всего ссылка устарела — возьми новую.',
      'en': 'Subscription not found (404). The link has most likely expired — get a new one.'
    },
    'fsub_forbidden': {
      'ru': 'Сервис не пустил нас к подписке. Возможно, она закончилась или закрыта для сторонних приложений.',
      'en': 'The service refused access to the subscription. It may have expired or be closed to third-party apps.'
    },
    'fsub_server': {
      'ru': 'У сервиса сейчас сбой на стороне сервера. Попробуй через несколько минут.',
      'en': 'That service is having a server-side problem. Try again in a few minutes.'
    },
    'fsub_empty': {
      'ru': 'Сервис ответил пустой подпиской. Проверь, что ссылка полная и не обрезалась при копировании.',
      'en': 'The service returned an empty subscription. Check the link was copied in full.'
    },
    'fsub_timeout': {
      'ru': 'Сервер не ответил вовремя. Если сейчас включён VPN — выключи его и попробуй снова.',
      'en': 'The server did not answer in time. If the VPN is on, turn it off and try again.'
    },
    // Формат ответа вообще не удалось разобрать: ни ссылок, ни конфига.
    'fsub_unreadable': {
      'ru': 'По этой ссылке не подписка, а что-то другое — ни одного сервера '
          'в ответе нет. Скопируй ссылку из своего сервиса ещё раз целиком.',
      'en': 'That link returns something other than a subscription — there are '
          'no servers in the response. Copy the full link from your provider again.'
    },
    // Серверы нашлись, но все — на протоколах, которых нет в нашем ядре.
    'fsub_other_proto': {
      'ru': 'Серверы в подписке есть, но все они работают по протоколам '
          '{list}. Наше приложение их пока не поднимает — оно умеет VLESS, '
          'VMess, Trojan и Shadowsocks. Если у сервиса есть ссылка с этими '
          'протоколами, подойдёт она.',
      'en': 'The subscription has servers, but all of them use {list}. The app '
          'does not support those yet — it works with VLESS, VMess, Trojan and '
          'Shadowsocks. If your provider offers a link with those, use it instead.'
    },
    // Разобрали формат, но список узлов внутри пустой.
    'fsub_no_servers': {
      'ru': 'Подписка открылась, но серверов в ней нет — похоже, она '
          'закончилась или ещё не выдана. Проверь её в своём сервисе.',
      'en': 'The subscription opened but contains no servers — it looks expired '
          'or not issued yet. Check it with your provider.'
    },
    // Часть серверов пропущена — не ошибка, а честное предупреждение.
    'fsub_partial': {
      'ru': 'Добавлено серверов: {ok}. Ещё {skipped} пропущено — они на '
          'протоколах {list}, их наше ядро не поддерживает.',
      'en': 'Added {ok} servers. {skipped} more were skipped — they use {list}, '
          'which the core does not support.'
    },
    'subs_until': {'ru': 'до {d}', 'en': 'until {d}'},
    'srv_ping_one': {'ru': 'Померить пинг этого сервера', 'en': 'Ping this server'},
    // --- вид списка серверов ---
    'view_grid': {'ru': 'Сеткой, по два в ряд', 'en': 'Grid, two per row'},
    'view_list': {'ru': 'Списком, крупно', 'en': 'List, large cards'},
    // --- поддержка ---
    'sup_empty_t': {'ru': 'Чем помочь?', 'en': 'How can we help?'},
    'sup_empty_b': {
      'ru':
          'Напиши прямо здесь — ответим в приложении. Обычно отвечаем в течение часа.',
      'en':
          'Write right here — we answer inside the app, usually within an hour.'
    },
    'sup_in_tg': {'ru': 'Написать в Telegram', 'en': 'Message us on Telegram'},
    // --- резервная копия настроек ---
    'backup': {'ru': 'Резервная копия', 'en': 'Backup'},
    'bk_intro': {
      'ru':
          'В копию попадают правила по приложениям, свои серверы, сайты в обход и настройки интерфейса. Подписка и доступ в файл НЕ записываются — файл можно спокойно хранить где угодно.',
      'en':
          'The copy holds per-app rules, your own servers, bypass sites and interface settings. Your subscription and access are NOT written to the file — keep it wherever you like.'
    },
    'bk_grp_copy': {'ru': 'Копия', 'en': 'Copy'},
    'bk_grp_reset': {'ru': 'Опасная зона', 'en': 'Danger zone'},
    'bk_export': {'ru': 'Сохранить в файл', 'en': 'Save to file'},
    'bk_export_d': {
      'ru': 'Создать файл с текущими настройками',
      'en': 'Create a file with your current settings'
    },
    'bk_import': {'ru': 'Восстановить из файла', 'en': 'Restore from file'},
    'bk_import_d': {
      'ru': 'Применить настройки из сохранённой копии',
      'en': 'Apply settings from a saved copy'
    },
    'bk_saved': {'ru': 'Сохранено настроек: {n}', 'en': 'Settings saved: {n}'},
    'bk_restored': {
      'ru': 'Восстановлено настроек: {n}',
      'en': 'Settings restored: {n}'
    },
    'bk_fail': {'ru': 'Не удалось сохранить', 'en': 'Could not save'},
    'bk_bad_file': {'ru': 'Файл не подошёл', 'en': 'File not accepted'},
    'bk_copied': {'ru': 'Путь скопирован', 'en': 'Path copied'},
    'bk_reset': {'ru': 'Сбросить настройки', 'en': 'Reset settings'},
    'bk_reset_d': {
      'ru': 'Вернуть всё к исходному виду. Подписка сохранится.',
      'en': 'Return everything to defaults. Your subscription stays.'
    },
    'bk_reset_q': {'ru': 'Сбросить настройки?', 'en': 'Reset settings?'},
    'bk_reset_body': {
      'ru':
          'Правила по приложениям, свои серверы, сайты в обход и настройки интерфейса вернутся к исходным. Подписка и привязка аккаунта останутся на месте.',
      'en':
          'Per-app rules, your own servers, bypass sites and interface settings return to defaults. Your subscription and account link stay.'
    },
    'bk_reset_done': {'ru': 'Настройки сброшены', 'en': 'Settings reset'},
    'subs_remove_q': {'ru': 'Убрать подписку?', 'en': 'Remove subscription?'},
    'subs_remove_body': {
      'ru':
          'Серверы {h} исчезнут из списка. Саму подписку это не отменяет — её можно добавить снова.',
      'en':
          'Servers from {h} will disappear from the list. This does not cancel the subscription itself — you can add it back.'
    },
    'sec_interface': {'ru': 'Интерфейс', 'en': 'Interface'},
    'sec_admin': {'ru': 'Администрирование', 'en': 'Administration'},
    'profile_sub': {'ru': 'Профиль и подписка', 'en': 'Profile & subscription'},
    'profile_sub_d': {
      'ru': 'Статус, продление, рефералка',
      'en': 'Status, renew, referral'
    },
    'channel': {'ru': 'Наш Telegram-канал', 'en': 'Our Telegram channel'},
    'autoconnect': {'ru': 'Автоподключение', 'en': 'Auto-connect'},
    'autoconnect_d': {
      'ru': 'VPN включается сам при запуске приложения',
      'en': 'The VPN connects itself when you open the app'
    },
    'bypass_ru': {'ru': 'Обход для РФ-сайтов', 'en': 'Bypass for RU sites'},
    'bypass_ru_d': {
      'ru': 'Российские сайты и приложения — напрямую, остальное — через VPN',
      'en': 'Russian sites and apps go direct, everything else through the VPN'
    },
    'protocol': {'ru': 'Протокол', 'en': 'Protocol'},
    'dns': {'ru': 'DNS', 'en': 'DNS'},
    'language': {'ru': 'Язык', 'en': 'Language'},
    'sound': {'ru': 'Звук подключения', 'en': 'Connection sound'},
    'sound_d': {
      'ru': 'Звук при подключении и отключении',
      'en': 'Sound on connect and disconnect'
    },
    'vibration': {'ru': 'Вибрация', 'en': 'Vibration'},
    'vibration_d': {
      'ru': 'Виброотклик при подключении',
      'en': 'Haptic feedback on connect'
    },
    'notif_server': {
      'ru': 'Уведомления',
      'en': 'Notifications'
    },
    'notif_server_d': {
      'ru': 'О подключении и смене сервера',
      'en': 'About connecting and server changes'
    },
    'stats': {'ru': 'Статистика', 'en': 'Statistics'},
    'stats_d': {
      'ru': 'Трафик за всё время, страны, графики',
      'en': 'All-time traffic, countries, charts'
    },
    'speedtest': {'ru': 'Тест скорости', 'en': 'Speed test'},
    'speedtest_d': {
      'ru': 'Замер скорости со спидометром',
      'en': 'Speed measurement with a gauge'
    },
    'ios_preview': {'ru': 'Стиль iOS', 'en': 'iOS style'},
    'ios_preview_d': {
      'ru': 'Тумблеры, стекло и шторки — пощупать',
      'en': 'Switches, glass and sheets — try them'
    },
    'how_connect': {'ru': 'Как подключиться', 'en': 'How to connect'},
    'how_connect_d': {
      'ru': 'Инструкция по подключению VPN',
      'en': 'VPN connection guide'
    },
    'logs': {'ru': 'Логи (что → куда идёт)', 'en': 'Logs (what goes where)'},
    'support': {'ru': 'Поддержка', 'en': 'Support'},
    'support_d': {
      'ru': 'Чат в приложении или Telegram',
      'en': 'In-app chat or Telegram'
    },
    'admin_panel': {'ru': 'Админ-панель', 'en': 'Admin panel'},
    'admin_panel_d': {
      'ru': 'Метрики, ошибки, ИИ-агент',
      'en': 'Metrics, errors, AI agent'
    },
    'logout': {'ru': 'Выйти из аккаунта', 'en': 'Log out'},

    // --- профиль ---
    'profile': {'ru': 'Профиль', 'en': 'Profile'},
    'account_not_linked': {
      'ru': 'Аккаунт не привязан',
      'en': 'Account not linked'
    },
    'sub_active': {'ru': 'Подписка активна', 'en': 'Subscription active'},
    'sub_inactive': {
      'ru': 'Подписка не активна',
      'en': 'Subscription inactive'
    },
    'full_access': {
      'ru': 'Полный доступ ко всем серверам',
      'en': 'Full access to all servers'
    },
    'subscribe_hint': {
      'ru': 'Оформи в боте для полного доступа',
      'en': 'Subscribe in the bot for full access'
    },
    'renew': {'ru': 'Продлить подписку', 'en': 'Renew subscription'},
    'subscribe': {'ru': 'Оформить подписку', 'en': 'Get subscription'},
    'invite': {'ru': 'Пригласить друга', 'en': 'Invite a friend'},
    'invite_d': {
      'ru': 'Реферальная ссылка и бонусы в боте',
      'en': 'Referral link and bonuses in the bot'
    },
    'our_channel': {'ru': 'Наш канал', 'en': 'Our channel'},
    'valid_until': {'ru': 'Действует до', 'en': 'Valid until'},
    'days_short': {'ru': 'дн.', 'en': 'd'},
    'servers_label': {'ru': 'Серверов', 'en': 'Servers'},
    'unit_mbps': {'ru': 'МБ/с', 'en': 'MB/s'},
    'unit_kbps': {'ru': 'КБ/с', 'en': 'KB/s'},
    'link_tg': {'ru': 'Привязать Telegram', 'en': 'Link Telegram'},
    'link_tg_d': {
      'ru': 'Синхронизировать подписку и статус',
      'en': 'Sync subscription and status'
    },
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
    'traffic': {'ru': 'Трафик', 'en': 'Traffic'},
    'st_ready': {'ru': 'Готов к тесту', 'en': 'Ready to test'},
    'st_done': {'ru': 'Готово', 'en': 'Done'},
    'st_fail': {
      'ru': 'Тест не прошёл — проверь соединение',
      'en': 'Test failed — check your connection'
    },
    'open_in_tg': {'ru': 'Открыть в Telegram', 'en': 'Open in Telegram'},
    'ping_settings': {'ru': 'Настройки пинга', 'en': 'Ping settings'},
    'ping_type': {'ru': 'Тип пинга', 'en': 'Ping type'},
    // Названия методов — словами, а не аббревиатурами: человек должен
    // понимать, что он выбирает, не зная сетевых терминов.
    // Короткие подписи для строки «Пинг» в настройках туннеля.
    'ping_short_tcp': {'ru': 'TCP', 'en': 'TCP'},
    'ping_short_proxy': {'ru': 'TLS', 'en': 'TLS'},
    'ping_m_tcp': {'ru': 'Быстрый (TCP)', 'en': 'Fast (TCP)'},
    'ping_m_tls': {'ru': 'Точный (TLS)', 'en': 'Accurate (TLS)'},
    'ping_proxy_d': {
      'ru': 'Медленнее, зато честно. Числа можно сравнивать между собой',
      'en': 'Slower but honest. The numbers are comparable with each other'
    },
    'ping_tcp_d': {
      'ru': 'Быстро. При включённом VPN сам переключается на точный',
      'en': 'Fast. Switches to accurate on its own when the VPN is on'
    },
    'ping_url_hint': {
      'ru': 'Куда стучимся при замере. Адрес влияет на числа, поэтому меняй,\n'
          'только если текущий недоступен',
      'en': 'Where we knock during a measurement. It affects the numbers, so\n'
          'change it only if the current one is unreachable'
    },
    'ping_test_url': {
      'ru': 'Адрес проверки',
      'en': 'Check address'
    },

    // --- сеть ---
    'net_settings': {'ru': 'Сеть и протокол', 'en': 'Network & protocol'},
    'net_settings_d': {
      'ru': 'Версия сети, DNS, обход блокировок',
      'en': 'Network version, DNS, anti-blocking'
    },
    'ip_type': {
      'ru': 'Тип адресов (IPv4 / IPv6)',
      'en': 'Address type (IPv4 / IPv6)'
    },
    'ip_type_hint': {
      'ru':
          'IPv4 — максимальная совместимость. IPv6 — если провайдер поддерживает. Менять только если понимаете, что делаете.',
      'en':
          'IPv4 — max compatibility. IPv6 — if your ISP supports it. Change only if you know what you are doing.'
    },
    'custom_dns': {'ru': 'Свой DNS', 'en': 'Custom DNS'},
    'custom_dns_hint': {
      'ru':
          'Через запятую. Пусто — DNS сервера по умолчанию. Менять только если понимаете, что делаете.',
      'en':
          'Comma-separated. Empty — server default DNS. Change only if you know what you are doing.'
    },
    'bg_keep': {
      'ru': 'Не усыплять приложение',
      'en': 'Keep the app awake'
    },
    'bg_keep_off': {
      'ru': 'Android усыпляет приложение, и оно не восстановит связь, '
          'если сервер отвалится. Разреши — будет чинить само',
      'en': 'Android puts the app to sleep, so it cannot restore the '
          'connection if a server drops. Allow it to fix that itself'
    },
    'bg_keep_on': {
      'ru': 'Приложение восстановит связь само, даже свёрнутым',
      'en': 'The app restores the connection itself, even when minimised'
    },
    'bg_keep_ok': {'ru': 'Разрешено', 'en': 'Allowed'},
    'fragment': {'ru': 'Фрагментирование', 'en': 'Fragmentation'},
    'fragment_d': {
      'ru': 'Разбивает начало соединения на части, чтобы провайдер не узнал '
          'в нём VPN. Включай, если обычное подключение не проходит.',
      'en': 'Splits the start of the connection into pieces so your provider '
          'cannot recognise it as a VPN. Turn on if the normal connection fails.'
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
    'split_enable': {
      'ru': 'Включить туннелирование трафика',
      'en': 'Enable split tunneling'
    },
    'split_hint_through': {
      'ru': 'Выбранные приложения идут через VPN, остальные — напрямую.',
      'en': 'Selected apps go through VPN, the rest go direct.'
    },
    'split_hint_bypass': {
      'ru': 'Выбранные приложения идут напрямую, остальные — через VPN.',
      'en': 'Selected apps go direct, the rest go through VPN.'
    },
    'split_bypass': {'ru': 'В обход VPN', 'en': 'Bypass VPN'},
    'split_bypass_sub': {
      'ru': 'Остальное — через VPN',
      'en': 'Rest — through VPN'
    },
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
    'adblock': {
      'ru': 'Блокировка рекламы и трекеров',
      'en': 'Ad & tracker blocking'
    },
    'adblock_d': {
      'ru': 'Реклама и трекеры блокируются',
      'en': 'Ads and trackers are blocked'
    },
    'smart_ai': {'ru': 'Умный доступ к ИИ', 'en': 'Smart AI access'},
    'smart_ai_d': {
      'ru': 'Любая нейросеть автоматически идёт через рабочий сервер',
      'en': 'Any AI service automatically goes through a working server'
    },
    // Без англицизма и без названий протоколов: человеку важно, что связь
    // не пропадёт, а не как это устроено внутри.
    'ondemand': {'ru': 'По требованию', 'en': 'On demand'},
    'ondemand_d': {
      'ru': 'Если связь оборвётся — вернём её сами',
      'en': 'If the connection drops, we bring it back'
    },
    'ks_nav': {
      'ru': 'Kill-switch (защита от утечек)',
      'en': 'Kill-switch (leak protection)'
    },
    'ks_nav_d': {
      'ru': 'Без VPN интернета не будет',
      'en': 'No VPN — no internet'
    },
    'cs_nav': {'ru': 'Свои серверы (JSON)', 'en': 'Custom servers (JSON)'},
    'cs_nav_d': {
      'ru': 'Для продвинутых · при активном подключении',
      'en': 'Advanced · while connected'
    },

    // --- двойной VPN ---

    // --- диагностика ---

    // --- kill-switch ---
    'ks_title': {
      'ru': 'Kill-switch (защита от утечек)',
      'en': 'Kill-switch (leak protection)'
    },
    'ks_intro': {
      'ru':
          'Настоящий Kill-switch — это системная функция Android. Она блокирует весь интернет, если VPN отключился, и работает даже при перезапуске или сбое приложения.',
      'en':
          'A real kill-switch is an Android system feature. It blocks all internet if the VPN drops and works even if the app restarts or crashes.'
    },
    'ks_how': {'ru': 'Как включить:', 'en': 'How to enable:'},
    'ks_s1': {
      'ru': 'Нажми кнопку ниже — откроются настройки VPN.',
      'en': 'Tap the button below — VPN settings will open.'
    },
    'ks_s2': {
      'ru': 'Возле «Various VPN» нажми ⚙️ (шестерёнку).',
      'en': 'Next to “Various VPN” tap ⚙️ (the gear).'
    },
    'ks_s3': {
      'ru': 'Включи «Постоянная VPN» (Always-on VPN).',
      'en': 'Turn on “Always-on VPN”.'
    },
    'ks_s4': {
      'ru': 'Включи «Блокировать соединения без VPN».',
      'en': 'Turn on “Block connections without VPN”.'
    },
    'ks_open': {'ru': 'Открыть настройки VPN', 'en': 'Open VPN settings'},
    'ks_hint': {
      'ru':
          'Подсказка: для «Постоянной VPN» подключение должно быть настроено — сначала хотя бы раз подключись к Various VPN.',
      'en':
          'Tip: for Always-on VPN a connection must exist — connect to Various VPN at least once first.'
    },

    // --- свои серверы ---
    'cs_title': {'ru': 'Свои серверы', 'en': 'Custom servers'},
    'cs_advanced': {'ru': 'Для продвинутых', 'en': 'For advanced users'},
    'cs_body': {
      'ru':
          'Добавь до 5 своих серверов. Подойдёт ссылка вида vless://…, список таких ссылок или файл настроек, выгруженный из другого VPN-приложения — сервер вытащим сами. Появятся рядом с нашими.',
      'en':
          'Add up to 5 of your own servers. A vless://… link, a list of them, or a settings file exported from another VPN app all work — we pull the server out ourselves. They appear next to ours.'
    },
    'cs_locked': {
      'ru':
          'Твоя подписка Various VPN неактивна — оформи её, и добавление своих серверов откроется.',
      'en':
          'Your Various VPN subscription is inactive — get one to unlock adding your own servers.'
    },
    'cs_paste': {'ru': 'Вставить из буфера', 'en': 'Paste from clipboard'},
    'cs_add': {'ru': 'Добавить серверы', 'en': 'Add servers'},

    // --- стрик / огонёк ---
    'streak_title_on': {
      'ru': 'Серия: {n} {w} подряд',
      'en': 'Streak: {n} {w} in a row'
    },
    'streak_title_off': {'ru': 'Начни серию!', 'en': 'Start a streak!'},
    'streak_hint_on': {
      'ru': 'Заходи каждый день — не потеряй огонёк 🔥',
      'en': 'Come back daily — don\'t lose the flame 🔥'
    },
    'streak_hint_off': {
      'ru': 'Подключай VPN каждый день и получай бонусные дни',
      'en': 'Connect the VPN daily and earn bonus days'
    },
    'streak_next': {
      'ru': 'До награды +{r} {rw}: осталось {d} {dw} (веха {m})',
      'en': 'To reward +{r} {rw}: {d} {dw} left (milestone {m})'
    },
    'streak_freezes': {
      'ru':
          'Заморозки: {n} · копятся за 25+ ч VPN в неделю и спасают серию при пропуске дня',
      'en':
          'Freezes: {n} · earned for 25+ h VPN a week, save your streak if you miss a day'
    },
    'streak_rewards': {'ru': 'Награды за серию', 'en': 'Streak rewards'},
    'streak_celebrate': {
      'ru': 'СЕРИЯ ПРОДОЛЖАЕТСЯ!',
      'en': 'STREAK CONTINUES!'
    },
    'streak_celebrate_sub': {
      'ru': '{n} {w} подряд с Various VPN',
      'en': '{n} {w} in a row with Various VPN'
    },
    'streak_reward_days': {
      'ru': '🎁  +{n} {w} подписки',
      'en': '🎁  +{n} {w} of subscription'
    },
    'streak_close': {
      'ru': 'Начислено автоматически · тапни, чтобы закрыть',
      'en': 'Credited automatically · tap to close'
    },
  };
}
