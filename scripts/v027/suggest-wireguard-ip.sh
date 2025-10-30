#!/bin/bash
# suggest-wireguard-ip.sh v1.2 — Julien's IP assignment helper

set -euo pipefail

WG_DIR="/home/julie/homelab/wireguard-clients"
SUBNET_BASE="10.4.0"
LOG="$WG_DIR/ip-suggestions.log"

if [[ ! -d "$WG_DIR" ]]; then
  echo "❌ ERROR: Directory $WG_DIR not found."
  exit 1
fi

echo "🔍 Scanning existing WireGuard client configs in $WG_DIR..."

ASSIGNED_IPS=()
DUPLICATES=()

for CONF in "$WG_DIR"/*/*.conf; do
  [[ -f "$CONF" ]] || continue
  IP=$(grep '^Address' "$CONF" | awk '{print $3}' | cut -d'/' -f1)
  if [[ -n "$IP" ]]; then
    if [[ " ${ASSIGNED_IPS[*]} " =~ " $IP " ]]; then
      DUPLICATES+=("$IP")
    else
      ASSIGNED_IPS+=("$IP")
    fi
  fi
done

echo -e "\n📓 Assigned IPs:"
printf '%s\n' "${ASSIGNED_IPS[@]}" | sort -V

if [[ ${#DUPLICATES[@]} -gt 0 ]]; then
  echo -e "\n⚠️ Duplicate IPs detected:"
  printf '%s\n' "${DUPLICATES[@]}" | sort -V
fi

for i in {2..254}; do
  CANDIDATE="$SUBNET_BASE.$i"
  if [[ ! " ${ASSIGNED_IPS[*]} " =~ " $CANDIDATE " ]]; then
    echo -e "\n✅ Next available IP: $CANDIDATE"
    echo "$(date -Iseconds) | Suggested IP: $CANDIDATE" >> "$LOG"
    exit 0
  fi
done

echo "❌ No available IPs found in $SUBNET_BASE.0/24"
exit 1
