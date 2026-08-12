#!/usr/bin/env bash
#
# Выкатка обновления бэкенда. Запускать на сервере из /opt/various-bot:
#
#   bash deploy/deploy.sh
#
# Смысл скрипта не в том, чтобы сэкономить три команды, а в порядке действий.
# Собрать образ ДО остановки старого — значит, что при неудачной сборке ничего
# не упало: бот продолжает работать на прежнем образе, а мы читаем ошибку.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Сохраняем базу"
# Копия делается КАЖДЫЙ раз, а не «когда что-то меняется в схеме»: сломать
# базу можно и обычным обновлением кода, а заметить это — через сутки.
cp -f various.db "various.db.bak-$(date +%Y%m%d-%H%M%S)"
ls -1t various.db.bak-* | tail -n +11 | xargs -r rm --   # держим последние 10

echo "==> Собираем образ"
docker compose -f deploy/docker-compose.yml build

echo "==> Перезапускаем"
docker compose -f deploy/docker-compose.yml up -d

echo "==> Проверяем, что поднялось"
sleep 5
docker compose -f deploy/docker-compose.yml ps

# Логи последних секунд: если бот падает на старте, он падает молча и
# перезапускается по кругу — в списке контейнеров это выглядит как «работает».
echo
echo "==> Последние строки логов (Ctrl+C — выйти)"
docker compose -f deploy/docker-compose.yml logs --tail=30
