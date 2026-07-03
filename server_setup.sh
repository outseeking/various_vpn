#!/bin/bash
# Ставит чистый Xray + Reality (VLESS-TCP :443 + VLESS-gRPC :8443).
# Аргумент $1 = имя (для ремарки), $2 = IP сервера.
set -e
NAME="$1"; IP="$2"
SNI="www.cloudflare.com"

# 1) освобождаем порты от Hiddify (останавливаем, не сносим полностью)
systemctl stop hiddify-haproxy hiddify-nginx hiddify-xray hiddify-singbox hiddify-ss-faketls shadowsocks-libev hiddify-panel 2>/dev/null || true
systemctl disable hiddify-haproxy hiddify-nginx hiddify-xray hiddify-singbox 2>/dev/null || true
sleep 1

# 2) ставим СОВМЕСТИМЫЙ Xray 1.8.24 (классический Reality; новый 26.x
#    несовместим со старым клиентом flutter_v2ray). Всегда переустанавливаем.
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 25.3.6 >/tmp/xrayinstall.log 2>&1
/usr/local/bin/xray version | head -1 || true

# 3) ключи Reality, uuid, shortId
KEYS=$(/usr/local/bin/xray x25519)
PRIV=$(echo "$KEYS" | grep -iE "private" | awk '{print $NF}')
PUB=$(echo "$KEYS"  | grep -iE "public"  | awk '{print $NF}')
UUID=$(cat /proc/sys/kernel/random/uuid)
SID=$(openssl rand -hex 8)

# 4) конфиг с двумя инбаундами
cat > /usr/local/etc/xray/config.json <<CFG
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0", "port": 443, "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {"show": false, "dest": "$SNI:443", "xver": 0,
          "serverNames": ["$SNI"], "privateKey": "$PRIV", "shortIds": ["$SID"]}
      },
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    },
    {
      "listen": "0.0.0.0", "port": 8443, "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID"}], "decryption": "none"},
      "streamSettings": {
        "network": "grpc", "security": "reality",
        "grpcSettings": {"serviceName": "grpc"},
        "realitySettings": {"show": false, "dest": "$SNI:443", "xver": 0,
          "serverNames": ["$SNI"], "privateKey": "$PRIV", "shortIds": ["$SID"]}
      },
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}, {"protocol": "blackhole", "tag": "block"}]
}
CFG

# 5) открыть порты (если ufw активен) и запустить
ufw allow 443/tcp >/dev/null 2>&1 || true
ufw allow 8443/tcp >/dev/null 2>&1 || true
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
systemctl is-active xray

# 6) вывести конфиги
echo "RESULT_START"
echo "vless://$UUID@$IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#$NAME TCP"
echo "vless://$UUID@$IP:8443?encryption=none&security=reality&sni=$SNI&fp=chrome&pbk=$PUB&sid=$SID&type=grpc&serviceName=grpc&mode=gun#$NAME gRPC"
echo "RESULT_END"
