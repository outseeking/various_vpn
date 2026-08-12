# -*- coding: utf-8 -*-
"""Фирменная графика Various VPN: баннеры разделов и карточка QR.

Здесь собрано всё, что бот показывает картинкой, — чтобы оформление жило в
одном месте и не расходилось по экранам. Раньше баннеры были готовыми файлами
1280×420 неизвестного происхождения: на экране телефона с плотностью 3x они
растягивались из полуторной ширины и выглядели мыльными.

Что делает модуль:

* рисует баннеры в 1920×640 — трёхкратный запас по плотности, текст остаётся
  резким на любом экране;
* умеет анимировать: по карточке идёт блик, а рамка переливается из лайма в
  фиолетовый. Анимация кодируется в MP4 (H.264), а не в GIF: GIF держит 256
  цветов, и плавный градиент в нём распадается на полосы;
* собирает карточку QR-кода — сам код при этом СТАТИЧЕН и максимально
  контрастен, движется только оправа. Мигающие модули часть сканеров не читает
  вовсе, а ради красоты ломать главную функцию нельзя.

Запуск: ``python brandkit.py`` — перерисовывает всё в assets/.
"""

from __future__ import annotations

import io
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BASE = Path(__file__).resolve().parent
ASSETS = BASE / "assets"
BANNERS = ASSETS / "banners"
FONTS = ASSETS / "fonts"

# --- палитра приложения ----------------------------------------------------
BG = (5, 7, 12)
INK = (233, 238, 246)
DIM = (152, 163, 180)
LIME = (143, 206, 27)
LIME_HI = (180, 226, 78)
VIOLET = (107, 52, 184)
VIOLET_HI = (123, 69, 200)

W, H = 1920, 640          # баннер раздела
FPS, SECONDS = 30, 4      # длина петли анимации


# --- шрифты ----------------------------------------------------------------
def font(size: int, weight: int = 700, family: str = "Exo2") -> ImageFont.FreeTypeFont:
    """Шрифт нужного начертания.

    Файлы вариативные: одно начертание задаётся осью веса. Если сборка Pillow
    осями не умеет, останется обычный Regular — рисунок от этого не сломается,
    просто заголовки будут светлее.
    """
    f = ImageFont.truetype(str(FONTS / f"{family}.ttf"), size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:  # noqa: BLE001 — сборка без поддержки осей
        pass
    return f


def text_w(d: ImageDraw.ImageDraw, s: str, f: ImageFont.FreeTypeFont) -> int:
    b = d.textbbox((0, 0), s, font=f)
    return b[2] - b[0]


# --- фон -------------------------------------------------------------------
def _mesh(w: int, h: int, phase: float) -> Image.Image:
    """Сетка меридианов — та же метафора, что и глобус в приложении.

    Считается через numpy: попиксельный цикл на кадре 1920×640 занимал бы
    секунды, а кадров сто двадцать.
    """
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    # Две системы дуг, идущих навстречу: получается ощущение объёма без 3D.
    a = np.sin((u * 26.0) + np.sin(v * 3.2 + phase) * 2.2 + phase * 1.7)
    b = np.sin((v * 14.0) - np.cos(u * 2.4 - phase) * 1.8 - phase * 1.1)
    lines = np.maximum(0.0, 1.0 - np.abs(a) * 11.0) + \
        np.maximum(0.0, 1.0 - np.abs(b) * 15.0)
    # Гасим сетку к центру: там лежит заголовок, и линии сквозь буквы
    # превращали его в решето.
    centre = 1.0 - np.exp(-(((u - 0.5) ** 2) / 0.055 + ((v - 0.5) ** 2) / 0.30))
    lines = np.clip(lines, 0, 1) * (0.22 + 0.34 * (1.0 - v)) * centre
    return Image.fromarray((lines * 255).astype(np.uint8), "L")


def _wash(w: int, h: int, phase: float) -> Image.Image:
    """Диагональная заливка лайм→фиолет, медленно проворачивающаяся."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    ang = 0.55 + 0.22 * math.sin(phase)
    t = (x * math.cos(ang) + y * math.sin(ang))
    t = (t - t.min()) / (t.max() - t.min())
    t = np.clip(t * 1.25 - 0.12, 0, 1)[..., None]

    lime = np.array(LIME, np.float32)
    viol = np.array(VIOLET, np.float32)
    base = np.array(BG, np.float32)
    grad = lime * (1 - t) + viol * t
    # Сильнее слева и справа, темнее по центру: середина остаётся под текст.
    edge = np.abs(np.linspace(-1, 1, w, dtype=np.float32))[None, :, None] ** 1.6
    mix = 0.10 + 0.52 * edge
    return Image.fromarray(
        np.clip(base * (1 - mix) + grad * mix, 0, 255).astype(np.uint8), "RGB")


def _sheen(w: int, h: int, phase: float) -> Image.Image:
    """Блик — узкая светлая полоса, проходящая по карточке слева направо."""
    x = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    pos = (phase / (2 * math.pi)) * 1.6 - 0.3
    d = np.abs((x - y * 0.35) - pos)
    band = np.clip(1.0 - d * 9.0, 0, 1) ** 2
    return Image.fromarray((band * 90).astype(np.uint8), "L")


def _scrim(w: int, h: int) -> Image.Image:
    """Тёмное пятно по центру — подложка под заголовок.

    Цветная заливка красива, но белый текст на ярко-зелёном участке терялся.
    Мягкое затемнение в середине держит контраст, не превращая фон в плашку.
    """
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w - 0.5, y / h - 0.5
    d = np.exp(-((u ** 2) / 0.075 + (v ** 2) / 0.42))
    return Image.fromarray((d * 210).astype(np.uint8), "L")


def backdrop(phase: float, w: int = W, h: int = H) -> Image.Image:
    """Фон карточки целиком: заливка + сетка + затемнение центра + блик."""
    img = _wash(w, h, phase)
    img = Image.composite(
        Image.new("RGB", (w, h), (215, 240, 170)), img,
        _mesh(w, h, phase).point(lambda v: int(v * 0.45)))
    img = Image.composite(Image.new("RGB", (w, h), BG), img, _scrim(w, h))
    img = Image.composite(Image.new("RGB", (w, h), (255, 255, 255)), img,
                          _sheen(w, h, phase))
    return img


def ramp(t: float) -> tuple[int, int, int]:
    """Фирменный переход лайм → фиолет.

    Через светлую середину, а не напрямую: лайм и фиолет почти
    противоположны, и прямая смесь на полпути даёт грязно-серый — линия
    выглядела выцветшей ровно посередине.
    """
    mid = (214, 236, 150)
    if t < 0.5:
        k = t * 2
        a, b = LIME_HI, mid
    else:
        k = (t - 0.5) * 2
        a, b = mid, VIOLET_HI
    return tuple(int(a[c] * (1 - k) + b[c] * k) for c in range(3))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1],
                                        radius=radius, fill=255)
    return m


def glow(layer: Image.Image, radius: int, strength: float) -> Image.Image:
    """Свечение вокруг светлых мест слоя."""
    g = layer.filter(ImageFilter.GaussianBlur(radius))
    return Image.blend(layer, Image.blend(layer, g, 1.0), strength)


# --- баннер раздела --------------------------------------------------------
SECTIONS = {
    "main": ("VARIOUS VPN", "Умный VPN нового поколения",
             "VARIOUS VPN", "Next-gen smart VPN"),
    "help": ("ПОМОЩЬ", "Подключение · о сервисе · поддержка",
             "HELP", "Setup · about · support"),
    "howto": ("КАК ПОДКЛЮЧИТЬ", "Три шага — и интернет свободен",
              "HOW TO CONNECT", "Three steps to a free internet"),
    "about": ("О СЕРВИСЕ", "Что умеет Various VPN",
              "ABOUT", "What Various VPN can do"),
    "support": ("ПОДДЕРЖКА", "Пишите — отвечаем быстро",
                "SUPPORT", "Message us — we reply fast"),
    "legal": ("ДОКУМЕНТЫ", "Условия, на которых работает сервис",
              "LEGAL", "The terms the service runs on"),
    "tariffs": ("ТАРИФЫ", "Выберите срок — доступ откроется сразу",
                "PLANS", "Pick a term — access opens at once"),
    "pay": ("ОПЛАТА", "Карта, криптовалюта или Telegram Stars",
            "PAYMENT", "Card, crypto or Telegram Stars"),
    "profile": ("ПРОФИЛЬ", "Подписка, устройства и статистика",
                "PROFILE", "Subscription, devices and stats"),
    "connect": ("ПОДКЛЮЧЕНИЕ", "Ссылка, QR-код и приложение",
                "CONNECT", "Link, QR code and the app"),
    "bonuses": ("БОНУСЫ", "Приглашайте друзей — получайте дни",
                "BONUSES", "Invite friends — get free days"),
    "trial": ("ТРИ ДНЯ БЕСПЛАТНО", "Без карты и автосписаний",
              "THREE DAYS FREE", "No card, no auto-charges"),
    "promo": ("ПРОМОКОД", "Введите код — дни добавятся сразу",
              "PROMO CODE", "Enter the code — days are added at once"),
    "app": ("ПРИЛОЖЕНИЕ", "Автовыбор сервера и раздельный туннель",
            "THE APP", "Auto server pick and split tunnel"),
}


def draw_title(bg: Image.Image, key: str, lang: str) -> Image.Image:
    """Печатает заголовок раздела поверх готового фона.

    Фон приходит снаружи и одинаков для всех разделов — так его считают один
    раз, а не заново для каждой надписи.
    """
    title_ru, sub_ru, title_en, sub_en = SECTIONS[key]
    title = title_en if lang == "en" else title_ru
    sub = sub_en if lang == "en" else sub_ru

    img = bg.copy()
    d = ImageDraw.Draw(img)

    # Длинные заголовки ужимаем, чтобы не упирались в края.
    size = 150 if key == "main" else 128
    ft = font(size, 800)
    while text_w(d, title, ft) > W - 260 and size > 64:
        size -= 6
        ft = font(size, 800)
    fs = font(44, 500, "Manrope")

    tw = text_w(d, title, ft)
    tx, ty = (W - tw) // 2, H // 2 - (size // 2) - 46

    # Тень под заголовком: на светлых участках заливки белый текст иначе
    # растворяется. Мягкая и тёмная — читается как объём, а не как обводка.
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).text((tx, ty), title, fill=190, font=ft)
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    img = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), img, shadow)
    d = ImageDraw.Draw(img)
    d.text((tx, ty), title, fill=INK, font=ft)

    sy = ty + size + 26
    d.text(((W - text_w(d, sub, fs)) // 2, sy), sub, fill=(226, 236, 246),
           font=fs)

    # Черта под подписью — из лайма в фиолет.
    lw, lh = 420, 6
    bar = Image.new("RGB", (lw, lh))
    bd = ImageDraw.Draw(bar)
    for i in range(lw):
        bd.line([(i, 0), (i, lh)], fill=ramp(i / lw))
    img.paste(bar, ((W - lw) // 2, sy + 76), rounded_mask((lw, lh), lh // 2))
    return img


def draw_banner(key: str, lang: str, phase: float) -> Image.Image:
    """Кадр раздела целиком — для одиночного предпросмотра."""
    return draw_title(backdrop(phase), key, lang)


# --- карточка QR -----------------------------------------------------------
QR = 1080


def qr_frame(phase: float,
             lang: str = "ru") -> tuple[Image.Image, tuple[int, int], int]:
    """Оправа карточки без кода: фон, рамка, уголки, подпись.

    Возвращает кадр, точку вклейки кода и его сторону. От ссылки не зависит —
    поэтому считается один раз на все карточки.
    """
    card = backdrop(phase, QR, QR + 150).convert("RGB")
    # Затемняем фон: карточка должна оставаться тёмной, цвет нужен по краям.
    card = Image.blend(card, Image.new("RGB", card.size, BG), 0.55)

    pad = 118
    side = QR - pad * 2

    # --- переливающаяся рамка ---
    #
    # Кольцо: широкий градиент, из которого маской вырезана полоса в несколько
    # пикселей. Так линия переливается по всей длине, а не красится одним
    # цветом.
    fx0, fy0 = pad - 62, pad - 62
    fw = side + 124
    ring = Image.new("RGB", (fw, fw))
    rd = ImageDraw.Draw(ring)
    for i in range(fw):
        t = (math.sin(i / fw * math.pi * 2 + phase * 2) + 1) / 2
        rd.line([(i, 0), (i, fw)], fill=ramp(t))
    outer = rounded_mask((fw, fw), 64)
    inner = Image.new("L", (fw, fw), 0)
    ImageDraw.Draw(inner).rounded_rectangle([7, 7, fw - 8, fw - 8],
                                            radius=57, fill=255)
    ring_mask = Image.fromarray(
        np.clip(np.asarray(outer, np.int16) - np.asarray(inner, np.int16),
                0, 255).astype(np.uint8), "L")

    # Свечение наружу — то самое «переливается», а не «нарисована линия».
    aura = Image.new("RGB", card.size, (0, 0, 0))
    aura.paste(ring, (fx0, fy0), ring_mask)
    aura = aura.filter(ImageFilter.GaussianBlur(26))
    card = Image.fromarray(np.clip(
        np.asarray(card, np.int16) + (np.asarray(aura, np.int16) * 0.9),
        0, 255).astype(np.uint8), "RGB")
    card.paste(ring, (fx0, fy0), ring_mask)

    # --- уголки-прицел ---
    d = ImageDraw.Draw(card)
    L, tw2, R = 108, 10, 64
    x0, y0, x1, y1 = fx0, fy0, fx0 + fw, fy0 + fw
    pulse = 0.65 + 0.35 * (math.sin(phase * 2) + 1) / 2
    ccol = tuple(int(LIME_HI[c] * pulse + INK[c] * (1 - pulse) * 0.25)
                 for c in range(3))
    for cx, cy, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1),
                           (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([(cx, cy + sy * R), (cx, cy + sy * (R + L))],
               fill=ccol, width=tw2)
        d.line([(cx + sx * R, cy), (cx + sx * (R + L), cy)],
               fill=ccol, width=tw2)

    # --- подпись ---
    ft = font(64, 800)
    fs = font(34, 500, "Manrope")
    title = "VARIOUS VPN"
    d.text(((QR - text_w(d, title, ft)) // 2, QR + 4), title, fill=INK, font=ft)
    hint = ("Наведи камеру — доступ откроется сам" if lang != "en"
            else "Point your camera — access opens by itself")
    d.text(((QR - text_w(d, hint, fs)) // 2, QR + 84), hint, fill=DIM, font=fs)

    return card, (pad, pad), side


def qr_plate(link: str, side: int) -> Image.Image:
    """Сам код на тёмной подложке. Единственное, что зависит от ссылки."""
    import qrcode

    # border=4 — «зона тишины» из спецификации QR: четыре модуля пустого поля
    # вокруг кода. Без неё сканеры теряют границу и читают через раз.
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_Q,
                       box_size=10, border=4)
    qr.add_data(link)
    qr.make(fit=True)
    # Белое на чёрном читается сканерами так же, как чёрное на белом, но в
    # тёмной карточке смотрится своим. Контраст держим предельный: любые
    # «фирменные» оттенки на самих модулях снижают надёжность считывания.
    code = qr.make_image(fill_color="#FFFFFF", back_color="#07090F").convert("RGB")
    return code.resize((side, side), Image.Resampling.NEAREST)


def draw_qr_card(link: str, phase: float = 0.0,
                 lang: str = "ru") -> Image.Image:
    """Одна статичная карточка — для запасного варианта и предпросмотра."""
    card, at, side = qr_frame(phase, lang)
    card = card.copy()
    card.paste(qr_plate(link, side), at)
    return card


# --- кодирование -----------------------------------------------------------
def encode_mp4(frames, size: tuple[int, int], out: Path,
               fps: int = FPS, preset: str = "slow") -> None:
    """Склеивает кадры в MP4 (H.264, без звука).

    Именно MP4, а не GIF: в GIF всего 256 цветов, и плавный переход лайма в
    фиолетовый рассыпается на полосы — ровно то, ради чего всё и делалось.
    Telegram показывает такой файл как анимацию, зациклено и без звука.
    """
    w, h = size
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}",
        "-r", str(fps), "-i", "-",
        "-an",
        "-c:v", "libx264", "-preset", preset, "-crf", "18",
        "-pix_fmt", "yuv420p",
        # faststart — чтобы клиент начинал показ, не скачав файл целиком.
        "-movflags", "+faststart",
        str(out),
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for fr in frames:
        p.stdin.write(fr.tobytes())
    p.stdin.close()
    if p.wait() != 0:
        raise RuntimeError("ffmpeg не смог собрать анимацию")


def phases(n: int):
    """Фазы одного полного цикла — чтобы петля сходилась без рывка."""
    return [i / n * 2 * math.pi for i in range(n)]


QR_ANIM = (720, 820)     # размер анимации карточки: хватает и на планшете
QR_FRAMES, QR_FPS = 45, 15


def qr_base(lang: str) -> Path:
    return BANNERS / f"qr_base{'_en' if lang == 'en' else ''}.mp4"


def qr_geom(lang: str) -> Path:
    return BANNERS / f"qr_base{'_en' if lang == 'en' else ''}.json"


def qr_animation(link: str, out: Path, lang: str = "ru") -> None:
    """Карточка QR по ссылке: код поверх заранее собранной оправы.

    Кадры оправы не поднимаются в Python вовсе — накладывает ffmpeg. Поэтому
    запрос обходится в доли секунды и не блокирует бота.
    """
    geom = json.loads(qr_geom(lang).read_text("utf-8"))
    with tempfile.TemporaryDirectory() as tmp:
        code_png = Path(tmp) / "code.png"
        qr_plate(link, geom["side"]).save(code_png)
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-stream_loop", "0", "-i", str(qr_base(lang)),
            "-i", str(code_png),
            "-filter_complex",
            f"[0:v][1:v]overlay={geom['x']}:{geom['y']}:format=rgb",
            "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(out),
        ]
        if subprocess.run(cmd).returncode != 0:
            raise RuntimeError("ffmpeg не смог наложить код на оправу")


def build_qr_base() -> None:
    """Рендерит оправу карточки в видео + запоминает, куда класть код.

    По одному ролику на язык: подпись под кодом на них разная, а собирать её
    на лету нельзя — тогда каждая карточка считалась бы минуту.
    """
    for lang in ("ru", "en"):
        box = None
        frames = []
        for i in range(QR_FRAMES):
            card, at, side = qr_frame(i / QR_FRAMES * 2 * math.pi, lang)
            k = QR_ANIM[0] / card.size[0]
            if box is None:
                box = {"x": round(at[0] * k), "y": round(at[1] * k),
                       "side": round(side * k)}
            frames.append(card.resize(QR_ANIM, Image.Resampling.LANCZOS))
        out = qr_base(lang)
        encode_mp4(frames, QR_ANIM, out, fps=QR_FPS, preset="slow")
        qr_geom(lang).write_text(json.dumps(box), "utf-8")
        print(f"оправа QR {out.name} {out.stat().st_size // 1024} КБ, {box}")


BG_BASE = BANNERS / "bg_base.mp4"


def build_bg_base() -> None:
    """Общий фон разделов — один файл на всех.

    Кадры отдаются генератором и уходят в ffmpeg по одному: держать их списком
    означало бы 442 МБ в памяти, которых на сервере просто нет.
    """
    n = FPS * SECONDS
    encode_mp4((backdrop(i / n * 2 * math.pi) for i in range(n)), (W, H),
               BG_BASE, preset="medium")
    print(f"фон {BG_BASE.name} {BG_BASE.stat().st_size // 1024} КБ")


def title_layer(key: str, lang: str) -> Image.Image:
    """Надпись раздела прозрачным слоем — накладывается поверх фона."""
    title_ru, sub_ru, title_en, sub_en = SECTIONS[key]
    title = title_en if lang == "en" else title_ru
    sub = sub_en if lang == "en" else sub_ru

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Длинные заголовки ужимаем, чтобы не упирались в края.
    size = 150 if key == "main" else 128
    ft = font(size, 800)
    while text_w(d, title, ft) > W - 260 and size > 64:
        size -= 6
        ft = font(size, 800)
    fs = font(44, 500, "Manrope")

    tx, ty = (W - text_w(d, title, ft)) // 2, H // 2 - (size // 2) - 46

    # Тень: на светлых участках заливки белый текст иначе растворяется.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx, ty), title, fill=(0, 0, 0, 210), font=ft)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))

    d = ImageDraw.Draw(img)
    d.text((tx, ty), title, fill=INK + (255,), font=ft)

    sy = ty + size + 26
    d.text(((W - text_w(d, sub, fs)) // 2, sy), sub,
           fill=(226, 236, 246, 255), font=fs)

    lw, lh = 420, 6
    bar = Image.new("RGB", (lw, lh))
    bd = ImageDraw.Draw(bar)
    for i in range(lw):
        bd.line([(i, 0), (i, lh)], fill=ramp(i / lw))
    img.paste(bar, ((W - lw) // 2, sy + 76), rounded_mask((lw, lh), lh // 2))
    return img


def build_all() -> None:
    """Пересобирает всю графику бота."""
    BANNERS.mkdir(parents=True, exist_ok=True)
    build_bg_base()

    with tempfile.TemporaryDirectory() as tmp:
        for key in SECTIONS:
            for lang in ("ru", "en"):
                suffix = "_en" if lang == "en" else ""
                layer = title_layer(key, lang)
                png = Path(tmp) / f"{key}{suffix}.png"
                layer.save(png)

                # Неподвижная надпись поверх движущегося фона — работа ffmpeg,
                # а не Python: секунда вместо минуты и никакой памяти.
                out = BANNERS / f"{key}{suffix}.mp4"
                cmd = [
                    "ffmpeg", "-y", "-loglevel", "error",
                    "-i", str(BG_BASE), "-i", str(png),
                    "-filter_complex", "[0:v][1:v]overlay=0:0",
                    "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out),
                ]
                if subprocess.run(cmd).returncode != 0:
                    raise RuntimeError(f"не собрался баннер {out.name}")

                # Первый кадр — на случай, если анимация где-то не подойдёт.
                still = backdrop(0.0).convert("RGBA")
                still.alpha_composite(layer)
                still.convert("RGB").save(BANNERS / f"{key}{suffix}.png",
                                          optimize=True)
                print(f"  {out.name} {out.stat().st_size // 1024} КБ")

    build_qr_base()
    build_intro()
    build_intro_sizes()


# --- ролик для страницы бота (то, что видно до нажатия Start) --------------
INTRO = (1920, 1080)

FEATURES = [
    ("bolt", "Молниеносно", "Blazing fast"),
    ("globe", "8+ серверов", "8+ servers"),
    ("lock", "Без логов", "No logs"),
    ("spark", "Умный подбор", "Smart routing"),
]


def glyph(d: ImageDraw.ImageDraw, kind: str, cx: float, cy: float,
          r: float, col: tuple[int, int, int]) -> None:
    """Рисует знак внутри кружка радиуса [r] с центром в (cx, cy)."""
    if kind == "bolt":
        k = r * 0.62
        d.polygon([(cx + k * 0.25, cy - k), (cx - k * 0.55, cy + k * 0.15),
                   (cx - k * 0.05, cy + k * 0.15), (cx - k * 0.25, cy + k),
                   (cx + k * 0.6, cy - k * 0.2), (cx + k * 0.1, cy - k * 0.2)],
                  fill=col)
    elif kind == "globe":
        k = r * 0.6
        d.ellipse([cx - k, cy - k, cx + k, cy + k], outline=col, width=4)
        d.line([(cx - k, cy), (cx + k, cy)], fill=col, width=4)
        d.arc([cx - k * 0.5, cy - k, cx + k * 0.5, cy + k], 0, 360,
              fill=col, width=4)
    elif kind == "lock":
        # Замок собирается из двух частей: сплошной корпус и дужка НАД ним.
        # Раньше дужка рисовалась поверх корпуса и её концы обрывались внутри
        # него — замок выглядел недорисованным.
        k = r * 0.5
        body_top = cy - k * 0.05
        sh = k * 0.62                       # ширина дужки
        # Дужка: полукруг плюс два прямых конца до корпуса.
        d.arc([cx - sh, body_top - k * 1.15, cx + sh, body_top + sh * 0.15],
              180, 0, fill=col, width=5)
        for sx in (-1, 1):
            x = cx + sx * sh
            d.line([(x, body_top - k * 0.5), (x, body_top)], fill=col, width=5)
        # Корпус — сплошной, с прорезью-скважиной: так силуэт читается сразу.
        d.rounded_rectangle([cx - k, body_top, cx + k, cy + k * 1.05],
                            radius=int(k * 0.3), fill=col)
        kh = k * 0.16
        d.ellipse([cx - kh, cy + k * 0.2 - kh, cx + kh, cy + k * 0.2 + kh],
                  fill=BG)
        d.line([(cx, cy + k * 0.2), (cx, cy + k * 0.6)], fill=BG, width=4)
    else:  # spark
        k = r * 0.66
        for a, b in ((k, k * 0.26), (k * 0.26, k)):
            d.polygon([(cx, cy - a), (cx + b, cy), (cx, cy + a),
                       (cx - b, cy)], fill=col)


def draw_intro(phase: float, lang: str = "both") -> Image.Image:
    """Кадр вступительного ролика: знак, название и четыре обещания.

    Подписи идут сразу на двух языках: эту страницу человек видит до нажатия
    Start, а язык интерфейса выбирается уже внутри бота. Показать один язык —
    значит потерять половину тех, кто зашёл.
    """
    w, h = INTRO
    img = backdrop(phase, w, h).convert("RGB")
    d = ImageDraw.Draw(img)

    # --- знак ---
    icon_path = ASSETS / "icon.png"
    if icon_path.exists():
        side = 280
        icon = Image.open(icon_path).convert("RGBA").resize(
            (side, side), Image.Resampling.LANCZOS)
        ix, iy = (w - side) // 2, 96
        # Ореол под знаком — он же держит его на пёстром фоне.
        halo = Image.new("RGB", (w, h), (0, 0, 0))
        halo.paste(Image.new("RGB", (side, side), (120, 170, 40)), (ix, iy),
                   icon.split()[3])
        halo = halo.filter(ImageFilter.GaussianBlur(70))
        img = Image.fromarray(np.clip(
            np.asarray(img, np.int16) + np.asarray(halo, np.int16),
            0, 255).astype(np.uint8), "RGB")
        img.paste(icon, (ix, iy), icon)
        d = ImageDraw.Draw(img)

    ft = font(126, 800)
    title = "VARIOUS VPN"
    d.text(((w - text_w(d, title, ft)) // 2, 418), title, fill=INK, font=ft)

    # Две строки подписи: русская крупнее, английская под ней потише — так
    # видно обе, но глаз не мечется между равными по весу надписями.
    fs = font(44, 600, "Manrope")
    fe = font(46, 500, "Manrope")
    d.text(((w - text_w(d, "Умный VPN нового поколения", fs)) // 2, 566),
           "Умный VPN нового поколения", fill=(226, 236, 246), font=fs)
    d.text(((w - text_w(d, "Next-gen smart VPN", fe)) // 2, 626),
           "Next-gen smart VPN", fill=DIM, font=fe)

    lw, lh = 560, 6
    bar = Image.new("RGB", (lw, lh))
    bd = ImageDraw.Draw(bar)
    for i in range(lw):
        bd.line([(i, 0), (i, lh)], fill=ramp(i / lw))
    img.paste(bar, ((w - lw) // 2, 692), rounded_mask((lw, lh), lh // 2))
    d = ImageDraw.Draw(img)

    # --- четыре обещания ---
    #
    # Загораются по очереди, бегущей волной: взгляд идёт слева направо и
    # прочитывает все четыре, а не выхватывает одно.
    ff = font(46, 700, "Manrope")
    fen = font(38, 500, "Manrope")
    cell = w // 4
    for i, (kind, ru, en) in enumerate(FEATURES):
        k = (math.sin(phase * 2 - i * 0.9) + 1) / 2
        col = tuple(int(DIM[c] + (LIME_HI[c] - DIM[c]) * k) for c in range(3))
        dim = tuple(int(c * 0.62) for c in col)
        cx = cell * i + cell // 2
        r = 40 + 4 * k
        d.ellipse([cx - r, 810 - r, cx + r, 810 + r], outline=col, width=5)
        glyph(d, kind, cx, 810, r, col)
        d.text((cx - text_w(d, ru, ff) // 2, 884), ru, fill=col, font=ff)
        d.text((cx - text_w(d, en, fen) // 2, 940), en, fill=dim, font=fen)

    return img


# Размеры, которые принимает BotFather для описания бота. Больший — первый.
INTRO_GIF_SIZES = ((960, 540), (640, 360), (320, 180))

GIF_FPS, GIF_SECONDS = 20, 3


def _intro_frames(tmp, n: int):
    """Кадры вступления на диск. На диск, а не в память: 1920×1080 × 45 штук —
    это 270 МБ, которых на этом сервере нет."""
    for i in range(n):
        draw_intro(i / n * 2 * math.pi).save(tmp / f"{i:04d}.png")


def build_intro_sizes() -> None:
    """Вступление во всех размерах, которые принимает BotFather.

    Видео — основной вариант: цвет в нём не урезан. GIF собираем рядом, на
    случай если понадобится именно он.
    """
    n = GIF_FPS * GIF_SECONDS
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        _intro_frames(tmp, n)
        src = str(tmp / "%04d.png")

        for w, h in INTRO_GIF_SIZES:
            scale = f"scale={w}:{h}:flags=lanczos"

            # --- видео ---
            #
            # crf 16 и preset veryslow: ролик короткий, вес всё равно копеечный,
            # а каждый лишний артефакт на градиенте виден сразу.
            mp4 = BANNERS / f"intro-{w}x{h}.mp4"
            r = subprocess.run([
                "ffmpeg", "-y", "-loglevel", "error",
                "-framerate", str(GIF_FPS), "-i", src,
                "-vf", scale, "-an",
                "-c:v", "libx264", "-preset", "veryslow", "-crf", "16",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)],
                capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f"видео не собралось: {r.stderr[:200]}")
            print(f"{mp4.name}: {mp4.stat().st_size // 1024} КБ")

            # --- GIF ---
            #
            # Палитра пересчитывается НА КАЖДЫЙ КАДР (stats_mode=single и
            # new=1). Одна палитра на весь ролик обязана описать все цвета,
            # через которые проходит переливание, и на каждый отдельный кадр
            # оттенков остаётся вчетверо меньше — отсюда и полосы. Своя палитра
            # на кадр отдаёт все 256 цветов текущей картинке.
            gif = BANNERS / f"intro-{w}x{h}.gif"
            pal = tmp / f"pal-{w}.png"
            r = subprocess.run([
                "ffmpeg", "-y", "-loglevel", "error",
                "-framerate", str(GIF_FPS), "-i", src,
                "-vf", f"{scale},palettegen=stats_mode=single:max_colors=256",
                str(pal)], capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f"палитра не собралась: {r.stderr[:200]}")
            r = subprocess.run([
                "ffmpeg", "-y", "-loglevel", "error",
                "-framerate", str(GIF_FPS), "-i", src, "-i", str(pal),
                "-lavfi", f"{scale}[x];[x][1:v]paletteuse=new=1:"
                          "dither=sierra2_4a",
                "-loop", "0", str(gif)], capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f"GIF не собрался: {r.stderr[:200]}")
            print(f"{gif.name}: {gif.stat().st_size // 1024} КБ")


def build_intro() -> None:
    """Ролик для страницы бота — тот, что видно до нажатия Start.

    Файл один на оба языка: до Start язык не переключить, поэтому обе надписи
    стоят на одном кадре.

    Ставится вручную через BotFather (Edit Bot → Description Picture): по API
    описание бота с медиа не меняется.
    """
    n = FPS * SECONDS
    out = BANNERS / "intro.mp4"
    # Генератор, а не список: кадр 1920×1080 весит 6 МБ, сто двадцать штук в
    # память этого сервера не поместятся.
    encode_mp4((draw_intro(i / n * 2 * math.pi) for i in range(n)),
               INTRO, out, preset="medium")
    draw_intro(0.0).save(BANNERS / "intro.png")
    # Прошлые раздельные версии убираем, чтобы не путались под руками.
    for stale in ("intro_en.mp4", "intro_en.png"):
        (BANNERS / stale).unlink(missing_ok=True)
    print(f"вступление {out.name} {out.stat().st_size // 1024} КБ")

if __name__ == "__main__":
    if not shutil.which("ffmpeg"):
        raise SystemExit("нужен ffmpeg: apt install ffmpeg")
    build_all()
