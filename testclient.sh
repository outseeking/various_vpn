#!/bin/bash
pkill -f tc.json 2>/dev/null; sleep 1
setsid /usr/local/bin/xray -c /root/tc.json >/root/tc.log 2>&1 < /dev/null &
sleep 4
echo "START_OK"
echo -n "curl-DE1-ya.ru: "
curl -s -x socks5h://127.0.0.1:10888 -m 12 -o /dev/null -w "HTTP=%{http_code}\n" https://ya.ru
echo -n "external-ip: "
curl -s -x socks5h://127.0.0.1:10888 -m 12 https://api.ipify.org
echo
echo "=== client log ==="
tail -6 /root/tc.log
pkill -f tc.json 2>/dev/null
