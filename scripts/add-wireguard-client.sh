#!/bin/bash
# add-wireguard-client.sh v1.3 — Julien's reproducible WireGuard client onboarding
#
# USAGE:
#   sudo ./add-wireguard-client.sh <client-name> <client-ip>
# EXAMPLE:
#   sudo ./add-wireguard-client.sh laptop 10.4.0.2

set -euo pipefail

# === CONFIG ===
WG_DIR="/home/julie/homelab/wireguard-clients"
WG_SUBNET="10.4.0.0/24"
LAN_SUBNET="192.168.50.0/24"
DNS_PRIMARY="192.168.50.4"
DNS_FALLBACK="192.168.50.1"
ENDPOINT="bardi.ch:51420"
MTU="1420"
LOG="$WG_DIR/onboarding.log"
WG_CONF="/etc/wireguard/wg0.conf"

# === USAGE CHECK ===
if [[ $# -ne 2 ]]; then
  echo "❌ ERROR: Missing arguments."
  echo "Usage: sudo ./add-wireguard-client.sh <client-name> <client-ip>"
  exit 1
fi

CLIENT_NAME="$1"
CLIENT_IP="$2"

mkdir -p "$WG_DIR/$CLIENT_NAME"
cd "$WG_DIR/$CLIENT_NAME"

echo "🔐 Generating keys for $CLIENT_NAME..."
wg genkey | tee "$CLIENT_NAME.key" | wg pubkey > "$CLIENT_NAME.pub"

SERVER_PRIV=$(grep '^PrivateKey' "$WG_CONF" | awk '{print $3}' || true)
if [[ -z "$SERVER_PRIV" ]]; then
  echo "❌ ERROR: Could not extract server PrivateKey from $WG_CONF"
  exit 1
fi

SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

cat > "$CLIENT_NAME.conf" <<EOF
# WireGuard client config — $CLIENT_NAME
# Created: $(date -Iseconds)

[Interface]
Address = $CLIENT_IP/24
PrivateKey = $(<"$CLIENT_NAME.key")
DNS = $DNS_PRIMARY, $DNS_FALLBACK
MTU = $MTU

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $ENDPOINT
AllowedIPs = $WG_SUBNET,$LAN_SUBNET
PersistentKeepalive = 25
EOF

echo -e "\n📱 Scan this QR code with WireGuard mobile app:\n"
qrencode -t ansiutf8 < "$CLIENT_NAME.conf"

echo -e "\n🔑 Add this to your server's wg0.conf:\n"
echo "[Peer]"
echo "PublicKey = $(<"$CLIENT_NAME.pub")"
echo "AllowedIPs = $CLIENT_IP/32"

echo "$(date -Iseconds) | $CLIENT_NAME | $CLIENT_IP" >> "$LOG"
echo -e "\n📝 Onboarding logged to $LOG"
