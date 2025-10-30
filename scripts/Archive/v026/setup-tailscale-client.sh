#!/bin/bash
# setup-tailscale-client.sh — Join NAS to Headscale tailnet as a client
# Author: Julien & Copilot
# Version: v2.5
#
# ⚠️ This script is specific to the NAS machine.
#
# Usage:
#   setup-tailscale-client.sh [--dry-run]
#   setup-tailscale-client.sh --remove
#   setup-tailscale-client.sh --reset-state
#
# Description:
#   - Runs `tailscale up` against your Headscale server
#   - Advertises LAN subnet(s) into the tailnet
#   - Ensures tailscaled service is enabled
#   - Logs version + timestamp for auditability
#   - Auto‑creates and enables setup-tailscale-client.service if missing
#   - Optional: --reset-state wipes /var/lib/tailscale/tailscaled.state and forces re‑auth
#   - Fetches the latest valid pre‑auth key tagged "tag:machine:nas" using .acl_tags
#   - If no valid key exists, exits with a hint to issue one
#   - Ensures DNS settings are configured in Headscale (nameserver + search domain)

set -euo pipefail

NAME="setup-tailscale-client"
SERVICE_PATH="/etc/systemd/system/${NAME}.service"
LOG_FILE="/var/log/${NAME}.log"
DRY_RUN=false
REMOVE=false
RESET_STATE=false

LOGIN_SERVER="https://nas.bardi.ch:8443"
ADVERTISE_ROUTES="192.168.50.0/24"
DNS_NAMESERVER="192.168.50.4"
DNS_DOMAIN="bardi.ch"

# === Fetch latest valid pre-auth key with tag:machine:nas ===
USER_ID=1   # replace with your actual numeric ID from `headscale users list`

CMD="sudo headscale preauthkeys list --user $USER_ID --output json"
TS_AUTHKEY="$($CMD \
  | jq -r '[.[] 
      | select(.expiration.seconds > now) 
      | select(.acl_tags[]? == "tag:machine:nas")] 
      | sort_by(.expiration.seconds) 
      | last 
      | .key // empty')"

if [[ -z "$TS_AUTHKEY" ]]; then
  echo "❌ No valid headscale key found with tag:machine:nas."
  echo "👉 Please issue one using:"
  echo "   sudo /home/julie/homelab/scripts/headscale-keys.sh new nas"
  exit 1
else
  echo "✅ TS_AUTHKEY retrieved (prefix: ${TS_AUTHKEY:0:6}..., length: ${#TS_AUTHKEY})"
fi

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
After=network-online.target

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
    --reset-state) RESET_STATE=true ;;
  esac
  shift
done

if $REMOVE; then
  remove_service
  exit 0
fi

RUN_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

log "🔧 Starting Tailscale client setup..."
log "🌐 Login server: $LOGIN_SERVER"
log "📡 Advertised routes: $ADVERTISE_ROUTES"
log "🔑 Using NAS-specific pre-auth key (prefix: ${TS_AUTHKEY:0:6}...)"

# Ensure tailscaled service is running
$DRY_RUN || sudo systemctl enable --now tailscaled

# === Optional reset of state ===
if $RESET_STATE; then
  log "⚠️ Resetting Tailscale state: wiping /var/lib/tailscale/tailscaled.state"
  $DRY_RUN || sudo systemctl stop tailscaled
  $DRY_RUN || sudo mv /var/lib/tailscale/tailscaled.state /var/lib/tailscale/tailscaled.state.$(date +%s).bak || true
  $DRY_RUN || sudo systemctl start tailscaled
fi

# === Conditional tailscale up ===
if tailscale status >/dev/null 2>&1 && ! $RESET_STATE; then
  log "ℹ️ Tailscale client already logged in — refreshing settings only."
  $DRY_RUN || sudo tailscale up \
    --advertise-routes="$ADVERTISE_ROUTES" \
    --accept-dns=true \
    --login-server="$LOGIN_SERVER"
else
  log "ℹ️ Fresh join — using login-server and NAS-specific authkey (force reauth)."
  $DRY_RUN || sudo tailscale up \
    --reset \
    --login-server="$LOGIN_SERVER" \
    --advertise-routes="$ADVERTISE_ROUTES" \
    --accept-dns=true \
    --authkey="$TS_AUTHKEY" \
    --force-reauth
fi

log "✅ Tailscale client configured."
log "🕒 Run timestamp: ${RUN_TIMESTAMP}"
log "TAILSCALE-CLIENT: version=v2.5 timestamp=${RUN_TIMESTAMP} routes=${ADVERTISE_ROUTES}"

create_service

echo "============================================================"
echo "✅ The NAS is now advertising $ADVERTISE_ROUTES."
echo
echo "👉 To approve this route in Headscale v0.26+:"
echo "   sudo headscale nodes list-routes"
echo "   sudo headscale nodes approve-routes --routes $ADVERTISE_ROUTES --identifier <id>"
echo
echo "After approval and DNS config, clients in your tailnet will be able to reach LAN devices"
echo "in $ADVERTISE_ROUTES and resolve hostnames like diskstation.$DNS_DOMAIN."
echo "============================================================"
