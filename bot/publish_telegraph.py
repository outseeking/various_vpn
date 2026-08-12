# -*- coding: utf-8 -*-
"""Публикует юридические документы на Telegraph и запоминает адреса страниц.

Зачем: раздел присылал документ пачкой сообщений — чат забивался тысячами
символов, а вернуться к нужному пункту потом было нельзя. Telegraph даёт
постоянную ссылку на страницу, которую можно открыть, переслать и указать в
оферте.

Страницы свои на каждый язык: у человека с английским интерфейсом кнопка
«Public offer» должна открывать английский текст, а не русский.

Скрипт можно гонять повторно: аккаунт и адреса страниц лежат в
``legal_pages.json``, при повторном запуске страницы РЕДАКТИРУЮТСЯ, а не
создаются заново — ссылки, которые кто-то уже сохранил, остаются рабочими.
"""
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.telegra.ph"
BASE = Path(__file__).resolve().parent
LEGAL_DIR = BASE / "legal"
STATE = BASE / "legal_pages.json"

# ключ, заголовок, файл — на каждый язык.
DOCS = {
    "ru": [
        ("priv", "Политика конфиденциальности",
         "01-politika-konfidencialnosti.md"),
        ("terms", "Пользовательское соглашение",
         "02-polzovatelskoe-soglashenie.md"),
        ("offer", "Публичная оферта", "03-publichnaya-oferta.md"),
        ("refund", "Условия возврата", "04-usloviya-vozvrata.md"),
        ("ref", "Реферальная программа", "05-referalnaya-programma.md"),
        ("pd", "Согласие на обработку данных", "06-soglasie-na-obrabotku.md"),
    ],
    "en": [
        ("priv", "Privacy policy", "en/01-privacy-policy.md"),
        ("terms", "Terms of service", "en/02-terms-of-service.md"),
        ("offer", "Public offer", "en/03-public-offer.md"),
        ("refund", "Refund policy", "en/04-refund-policy.md"),
        ("ref", "Referral programme", "en/05-referral-programme.md"),
        ("pd", "Consent to data processing",
         "en/06-consent-to-data-processing.md"),
    ],
}

_BOLD = re.compile(r"\*\*(.+?)\*\*", re.S)
_ITALIC = re.compile(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", re.S)


def call(method, **params):
    data = urllib.parse.urlencode(
        {k: (v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))
         for k, v in params.items()}
    ).encode()
    with urllib.request.urlopen(f"{API}/{method}", data=data, timeout=30) as r:
        out = json.load(r)
    if not out.get("ok"):
        raise RuntimeError(f"{method}: {out.get('error')}")
    return out["result"]


def inline(text):
    """Строка → узлы Telegraph. Понимаем **жирный** и *курсив* — больше в наших
    документах ничего и нет, а лишний разбор ломался бы на юридических скобках."""
    nodes, pos = [], 0
    for m in re.finditer(r"\*\*(.+?)\*\*|(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)",
                         text, re.S):
        if m.start() > pos:
            nodes.append(text[pos:m.start()])
        if m.group(1) is not None:
            nodes.append({"tag": "strong", "children": [m.group(1)]})
        else:
            nodes.append({"tag": "em", "children": [m.group(2)]})
        pos = m.end()
    if pos < len(text):
        nodes.append(text[pos:])
    return nodes or [""]


def to_nodes(md):
    """Markdown → содержимое страницы Telegraph.

    Заголовок первого уровня пропускаем: он и так стоит заголовком страницы,
    иначе название дублировалось бы дважды подряд.
    """
    nodes, para, first_h1 = [], [], True

    def flush():
        if para:
            nodes.append({"tag": "p", "children": inline(" ".join(para))})
            para.clear()

    for raw in md.splitlines():
        line = raw.strip()
        if not line:
            flush()
            continue
        if set(line) == {"-"}:
            flush()
            nodes.append({"tag": "hr"})
            continue
        if line.startswith("#"):
            flush()
            level = len(line) - len(line.lstrip("#"))
            title = line.lstrip("#").strip()
            if level == 1 and first_h1:
                first_h1 = False
                continue
            nodes.append({"tag": "h3" if level <= 2 else "h4",
                          "children": inline(title)})
            continue
        if line.startswith(("- ", "* ", "• ")):
            flush()
            nodes.append({"tag": "p", "children": inline("• " + line[2:])})
            continue
        para.append(line)
    flush()
    return nodes


state = json.loads(STATE.read_text("utf-8")) if STATE.exists() else {}

if "token" not in state:
    acc = call("createAccount", short_name="VariousVPN",
               author_name="Various VPN", author_url="https://t.me/variousvpn")
    state["token"] = acc["access_token"]
    print("аккаунт Telegraph создан")

# Старый формат — плоский {ключ: страница} без языка. Переносим его в «ru»,
# чтобы уже опубликованные русские страницы сохранили свои адреса.
pages = state.setdefault("pages", {})
if pages and not set(pages) <= {"ru", "en"}:
    state["pages"] = {"ru": pages}
    pages = state["pages"]
pages.setdefault("ru", {})
pages.setdefault("en", {})

for lang, docs in DOCS.items():
    for key, title, fname in docs:
        path_md = LEGAL_DIR / fname
        if not path_md.exists():
            print(f"пропуск {lang}/{key}: нет файла {fname}")
            continue
        nodes = to_nodes(path_md.read_text("utf-8"))
        path = pages[lang].get(key, {}).get("path")
        if path:
            res = call("editPage", access_token=state["token"], path=path,
                       title=title, content=nodes, author_name="Various VPN",
                       author_url="https://t.me/variousvpn")
            what = "обновлена"
        else:
            res = call("createPage", access_token=state["token"], title=title,
                       content=nodes, author_name="Various VPN",
                       author_url="https://t.me/variousvpn")
            what = "создана"
        pages[lang][key] = {"path": res["path"], "url": res["url"]}
        print(f"[{lang}] {what}: {title} — {res['url']}")

STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), "utf-8")
print("\nадреса сохранены в", STATE)
