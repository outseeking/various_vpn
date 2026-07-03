#!/bin/bash
IP="$1"; UUID="$2"; PBK="$3"; SID="$4"; NAME="$5"
cat > /root/tc.json <<CFG
{"inbounds":[{"port":10890,"listen":"127.0.0.1","protocol":"socks"}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"$IP","port":443,"users":[{"id":"$UUID","encryption":"none","flow":"xtls-rprx-vision"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.cloudflare.com","fingerprint":"chrome","publicKey":"$PBK","shortId":"$SID"}}}]}
CFG
pkill -f tc.json 2>/dev/null; sleep 1
setsid /usr/local/bin/xray -c /root/tc.json >/root/tc.log 2>&1 </dev/null &
sleep 4
echo -n "$NAME HTTP="; curl -s -x socks5h://127.0.0.1:10890 -m 12 -o /dev/null -w "%{http_code}" https://ya.ru; echo
echo -n "$NAME IP="; curl -s -x socks5h://127.0.0.1:10890 -m 12 https://api.ipify.org; echo
pkill -f tc.json 2>/dev/null
