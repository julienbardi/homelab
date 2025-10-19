#!/bin/bash
# setup-subnet-router.sh — Subnet router setup with systemd integration
# Author: Julien & Copilot
# Version: v2.0
#
# Usage:
#   setup-subnet-router.sh [--dry-run]
#   setup-subnet-router.sh --remove
#
# Description:
#   - Detects LAN subnets (excluding Docker conflicts)
#   - Configures NAT, dnsmasq, Tailscale route advertisement, GRO tuning
#   - Logs to /var/log/setup-subnet-router.log with Git commit hash if available
#   - Auto‑creates and enables setup-subnet-router.service if missing

set -euo pipefail

NAME="setup-subnet-router"
SERVICE_PATH="/etc/systemd/system/${NAME}.service"
LOG_FILE="/var/log/${NAME}.log"
DRY_RUN=false
REMOVE=false

# Detect Git commit if inside repo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_COMMIT=$(git rev-parse --short HEAD)
else
  GIT_COMMIT="no-git"
fi

log() { echo "$(date '+%F %T') | [$NAME][$GIT_COMMIT] $1" | tee -a "$LOG_FILE"; }

# === Service management ===
create_service() {
  UNIT="[Unit]
Description=$NAME service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/${NAME}.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target"

  if [ ! -f "$SERVICE_PATH" ]; then
    log "Creating $NAME.service"
    $DRY_RUN || echo "$UNIT" | sudo tee "$SERVICE_PATH" > /dev/null
    $DRY_RUN || sudo systemctl enable "$NAME.service"
  else
    log "$NAME.service already exists"
  fi
}

remove_service() {
  log "Removing $NAME.service"
  $DRY_RUN || sudo systemctl stop "$NAME.service"
  $DRY_RUN || sudo systemctl disable "$NAME.service"
  $DRY_RUN || sudo rm -f "$SERVICE_PATH"
}

# === Parse args ===
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --remove) REMOVE=true ;;
  esac
  shift
done

if $REMOVE; then
  remove_service
  exit 0
fi

# === Config toggles ===
ADVERTISE_DOCKER=true
SAFE_LAN_REGEX='^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1]))'

log "🔧 Starting subnet router setup..."
log "🔎 Available IPv4 addresses:"
ip -o -f inet addr show | awk '{print $2, $4}'

# === Detect LAN subnet(s) ===
LAN_SUBNETS=$(
  ip -o -f inet addr show \
  | awk '$2 !~ /tailscale|lo/ {print $2, $4}' \
  | while read -r iface cidr; do
      net=$(echo "$cidr" | awk -F'[./]' '{printf "%s.%s.%s.0/%s\n",$1,$2,$3,$5}')
      case "$iface" in
        docker*|br-*|virbr*)
          if [ "$ADVERTISE_DOCKER" = true ]; then
            if [[ "$net" =~ ^172\.1[6789]\. || "$net" =~ ^172\.2[0-9]\. || "$net" =~ ^172\.3[01]\. || "$net" =~ ^172\.17\. || "$net" =~ ^172\.18\. || "$net" =~ ^172\.19\. ]]; then
              log "⚠️ Conflict risk: $net is a common Docker subnet, auto‑excluded."
              continue
            fi
            echo "$net"
          else
            log "⚠️ Skipping $net ($iface, auto‑excluded)"
          fi
          ;;
        *) echo "$net" ;;
      esac
    done \
  | grep -E "$SAFE_LAN_REGEX" \
  | sort -u
)

if [[ -z "${LAN_SUBNETS}" ]]; then
  log "❌ No private LAN subnets detected. Exiting."
  exit 1
fi

log "✅ Detected LAN subnets: ${LAN_SUBNETS}"

TAILSCALE_IF="tailscale0"
RUN_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# === Enable IPv4 forwarding ===
sysctl -w net.ipv4.ip_forward=1 || log "⚠️ Could not enable IP forwarding."

# === NAT rules ===
iptables -t nat -D POSTROUTING -o "${TAILSCALE_IF}" -j MASQUERADE 2>/dev/null || true
for SUBNET in ${LAN_SUBNETS}; do
  iptables -t nat -A POSTROUTING -s "${SUBNET}" -o "${TAILSCALE_IF}" -j MASQUERADE || true
  log "✅ NAT MASQUERADE added for ${SUBNET} -> ${TAILSCALE_IF}"
done

# === Restart dnsmasq ===
if systemctl restart dnsmasq 2>/dev/null; then
  log "✅ dnsmasq restarted."
else
  log "⚠️ dnsmasq restart failed or not available."
fi

# === Tailscale route advertisement ===
ADV_LIST="$(echo "${LAN_SUBNETS}" | tr ' ' ',')"
if tailscale set --advertise-routes="${ADV_LIST}" 2>/dev/null; then
  log "✅ Tailscale advertising routes: ${ADV_LIST}"
else
  log "⚠️ Tailscale route advertisement failed."
fi

# === GRO tuning ===
ethtool -K "${TAILSCALE_IF}" gro off 2>/dev/null || log "ℹ️ GRO disable not supported."
ethtool -K "${TAILSCALE_IF}" rx-udp-gro-forwarding on 2>/dev/null || log "ℹ️ rx-udp-gro-forwarding not supported."
ethtool -K wg0 gro on 2>/dev/null || log "ℹ️ GRO enable not supported on wg0."

# === Footer / logging ===
log "✅ Subnet router setup complete."
log "👉 Approve these subnets in the Tailscale admin panel if needed: ${ADV_LIST}"
log "🕒 Run timestamp: ${RUN_TIMESTAMP}"
log "SUBNET-ROUTER: timestamp=${RUN_TIMESTAMP} subnets=${ADV_LIST}"

create_service

