"""Раздел «Юридическая информация» для бота Various VPN.

Документы лежат на Telegraph, кнопки ведут прямо на страницы. Пересылать текст
сообщениями оказалось плохо: документ на десять тысяч символов рвался на куски,
забивал чат и не давал ни сослаться на пункт, ни вернуться к нему потом. У
страницы есть постоянный адрес — его можно открыть, переслать и указать в
оферте.

Страницы свои на каждый язык: у человека с английским интерфейсом кнопка
«Public offer» должна открывать английский текст, а не русский. Адреса лежат в
``legal_pages.json`` рядом с этим файлом и создаются скриптом
``publish_telegraph.py``.

Правка документа: поменять ``legal/*.md`` (или ``legal/en/*.md``) и прогнать
скрипт заново — страницы обновятся по тем же адресам, уже сохранённые кем-то
ссылки останутся рабочими.

Подключение в основном файле бота:

    from app.bot.legal import legal_router

    dp.include_router(legal_router)

и в клавиатуре раздела «Помощь» — кнопка с ``callback_data="legal:menu"``.
"""

from __future__ import annotations

import json
from pathlib import Path

from aiogram import F, Router
from aiogram.filters import CommandStart
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)

legal_router = Router(name="legal")

PAGES_FILE = Path(__file__).with_name("legal_pages.json")

# Порядок здесь = порядок кнопок. Ключ короткий: он связывает документ с его
# страницей в legal_pages.json.
DOCS: list[tuple[str, str, str]] = [
    ("priv", "Политика конфиденциальности", "Privacy policy"),
    ("terms", "Пользовательское соглашение", "Terms of service"),
    ("offer", "Публичная оферта", "Public offer"),
    ("refund", "Условия возврата", "Refund policy"),
    ("ref", "Реферальная программа", "Referral programme"),
    ("pd", "Согласие на обработку данных", "Consent to data processing"),
]

MENU_TEXT = {
    "ru": (
        "⚖️ <b>Юридическая информация</b>\n\n"
        "Документы, на условиях которых работает Various VPN. "
        "Любой открывается страницей — её можно сохранить и переслать."
    ),
    "en": (
        "⚖️ <b>Legal information</b>\n\n"
        "The documents Various VPN operates under. Each one opens as a page "
        "you can save and forward."
    ),
}

# Кнопка для раздела «Помощь». Ставится вместо «Пользовательского соглашения»:
# соглашение — лишь один из шести документов, и отдельной кнопкой оно закрывало
# собой остальные пять.
LEGAL_BUTTON = InlineKeyboardButton(
    text="Юридическая информация", callback_data="legal:menu", style="success"
)


def _pages(lang: str) -> dict[str, str]:
    """Адреса страниц нужного языка. Читаем при каждом показе: документы можно
    перевыпустить скриптом, не трогая бота и не перезапуская его.

    Если английской страницы ещё нет, отдаём русскую: ссылка на документ на
    чужом языке всё же лучше, чем пропавшая из списка строка.
    """
    try:
        data = json.loads(PAGES_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    pages = data.get("pages", {})
    ru = {k: v.get("url", "") for k, v in pages.get("ru", {}).items()}
    if lang != "en":
        return ru
    en = {k: v.get("url", "") for k, v in pages.get("en", {}).items()}
    return {k: en.get(k) or ru.get(k, "") for k in set(ru) | set(en)}


def legal_menu_kb(lang: str = "ru") -> InlineKeyboardMarkup:
    """Список документов ссылками + красная кнопка возврата.

    Документ без адреса кнопкой не показываем: мёртвая кнопка хуже, чем её
    отсутствие — человек жмёт и не понимает, почему ничего не произошло.
    """
    en = lang == "en"
    urls = _pages(lang)
    # Синий — «primary»: это переход к чтению, а не действие над аккаунтом.
    # Зелёным и красным в боте помечены согласие и выход, и документы в этот
    # ряд не встают.
    rows = [[InlineKeyboardButton(text=(title_en if en else title_ru),
                                  url=urls[key], style="primary")]
            for key, title_ru, title_en in DOCS if urls.get(key)]
    rows.append([InlineKeyboardButton(
        text="Назад" if not en else "Back",
        callback_data="legal:back", style="danger")])
    return InlineKeyboardMarkup(inline_keyboard=rows)


@legal_router.callback_query(F.data == "legal:menu")
async def show_menu(cb: CallbackQuery) -> None:
    """Список документов — той же карточкой, что и остальные разделы бота.

    Именно карточкой, а не ``edit_text``: разделы живут одним фото-сообщением,
    а текстовую правку фото Telegram не разрешает — на этом кнопка раздела
    когда-то и оказалась мёртвой.
    """
    from app.bot.handlers import _send_card
    from app.bot.store import store

    user, _ = store.get_or_create(cb.from_user.id)
    lang = "en" if user.lang == "en" else "ru"
    await _send_card(cb.message, "help", MENU_TEXT[lang],
                     reply_markup=legal_menu_kb(lang), lang=user.lang)
    await cb.answer()


@legal_router.callback_query(F.data == "legal:back")
async def back_to_help(cb: CallbackQuery) -> None:
    """Возврат в раздел «Помощь», откуда сюда и пришли.

    Импорт внутри функции, а не сверху файла: ``handlers`` тянет клавиатуры, а
    те — этот модуль, и импорт на уровне файла замкнул бы круг.
    """
    from app.bot.handlers import on_help

    await on_help(cb)


@legal_router.message(CommandStart(deep_link=True, magic=F.args == "legal"))
async def deep_link(message: Message) -> None:
    """Переход из приложения по ссылке ``t.me/<бот>?start=legal``."""
    from app.bot.store import store

    user, _ = store.get_or_create(message.from_user.id)
    lang = "en" if user.lang == "en" else "ru"
    await message.answer(MENU_TEXT[lang], reply_markup=legal_menu_kb(lang),
                         parse_mode="HTML")
