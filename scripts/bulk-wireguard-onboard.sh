#!/bin/bash
# bulk-wireguard-onboard.sh v1.0 — Julien's LAN-to-WireGuard onboarding tool
#
# USAGE:
#   sudo ./bulk-wireguard-onboard.sh
#
# DESCRIPTION:
#   - Scans LAN using arp-scan on bridge0
#   - Maps each LAN IP (192.168.50.X) → WireGuard IP (10.4.0.X)
#   - Assigns client name as host-X or MAC suffix
#   - Calls add-wireguard-client.sh for each
#   - Logs onboarding to bulk-onboarding.log

set -euo pipefail

WG_DIR="/home/julie/homelab/wireguard-clients"
SCRIPT_DIR="/home/julie/homelab/scripts"
LOG="$WG_DIR/bulk-onboarding.log"
INTERFACE="bridge0"
SUBNET_PREFIX="192.168.50"
WG_PREFIX="10.4.0"

echo "🔍 Scanning LAN via arp-scan on $INTERFACE..."
SCAN=$(arp-scan --interface "$INTERFACE" --localnet | grep "$SUBNET_PREFIX" || true)

if [[ -z "$SCAN" ]]; then
  echo "❌ No LAN devices found. Is bridge0 active?"
  exit 1
fi

echo "$SCAN" | while read -r line; do
  LAN_IP=$(echo "$line" | awk '{print $1}')
  MAC=$(echo "$line" | awk '{print $2}')
  LAST_OCTET=$(echo "$LAN_IP" | cut -d. -f4)
  WG_IP="$WG_PREFIX.$LAST_OCTET"
  CLIENT_NAME="host-$LAST_OCTET"

  echo -e "\n📡 Found $LAN_IP ($MAC) → WireGuard $WG_IP as $CLIENT_NAME"

  # Skip known infrastructure
  if [[ "$LAN_IP" == "$SUBNET_PREFIX.1" || "$LAN_IP" == "$SUBNET_PREFIX.4" ]]; then
    echo "⏭️ Skipping infrastructure IP $LAN_IP"
    continue
  fi

  # Check if config already exists
  if [[ -f "$WG_DIR/$CLIENT_NAME/$CLIENT_NAME.conf" ]]; then
    echo "⚠️ Config for $CLIENT_NAME already exists. Skipping."
    continue
  fi

  echo "🚀 Onboarding $CLIENT_NAME..."
  sudo "$SCRIPT_DIR/add-wireguard-client.sh" "$CLIENT_NAME" "$WG_IP"

  echo "$(date -Iseconds) | $CLIENT_NAME | $LAN_IP → $WG_IP | $MAC" >> "$LOG"
done

echo -e "\n✅ Bulk onboarding complete. Log saved to $LOG"
