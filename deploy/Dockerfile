# Бот и сервер подписок — один образ на оба.
#
# Образ общий намеренно: код у них общий, зависимости тоже, а расходятся они
# только командой запуска. Два образа пришлось бы собирать и обновлять парой,
# и рано или поздно они разъехались бы по версиям библиотек.
FROM python:3.10-slim

# Часовой пояс сервера. Бот шлёт напоминания об окончании подписки по
# расписанию, и в UTC они приходили бы людям среди ночи.
ENV TZ=Europe/Moscow \
    PYTHONUNBUFFERED=1 \
    PYTHONUTF8=1 \
    PYTHONWARNINGS=ignore \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Зависимости отдельным слоем, ДО кода: правки в коде тогда не заставляют
# заново качать полсотни пакетов, и выкатка занимает секунды вместо минут.
COPY requirements.txt .
# ffmpeg собирает анимации для баннеров бота (brandkit.py), шрифты нужны ему же
# для подписей. В образе python:slim нет ни того, ни другого.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ffmpeg \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir -r requirements.txt \
    # Эти три в requirements.txt не попали — их ставили руками прямо в
    # окружение сервера. Ровно такой случай контейнеры и лечат: собери образ
    # без них, и бот молча упадёт на первой же картинке.
    && pip install --no-cache-dir \
        "pillow>=12.3" \
        "numpy>=2.2" \
        "qrcode>=8.2"

COPY . .

# Команду задаёт compose: бот и сервер подписок стартуют по-разному.
CMD ["python", "-m", "app.bot.main"]
