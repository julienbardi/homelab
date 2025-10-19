#!/bin/bash
# run-wg-easy.sh — Deploy and manage wg-easy VPN container with systemd integration
# Author: Julien & Copilot
# Version: v2.2
#
# Usage:
#   run-wg-easy.sh
#   run-wg-easy.sh --remove
#   run-wg-easy.sh --reset-password
#   run-wg-easy.sh --check
#
# Description:
#   - Stores secrets in /etc/wg-easy/wg-easy.env (dir 700, file 600)
#   - Ensures wg-easy.env contains PASSWORD_HASH (bcrypt)
#   - Deploys wg-easy container with host networking and persistent volume
#   - Configures NAT rule for VPN subnet → LAN subnet (idempotent, scoped)
#   - Syncs script into /usr/local/bin/run-wg-easy.sh
#   - Auto‑creates and enables /etc/systemd/system/wg-easy.service
#   - Restarts service if script or unit changed, starts if inactive
#   - Supports --reset-password to rotate admin password safely
#   - Supports --remove to cleanly uninstall container, env, NAT, and service
#   - Supports --check to print a health report without making changes
#   - Logs version + timestamp at completion for audit trail
#
# Files created/updated by this script:
#   /etc/wg-easy/                  → secure directory for secrets (chmod 700)
#   /etc/wg-easy/wg-easy.env       → environment file with PASSWORD_HASH (chmod 600)
#   /var/lib/wg-easy/              → persistent Docker volume for wg-easy data
#   /usr/local/bin/run-wg-easy.sh  → deployed copy of this script (chmod +x)
#   /etc/systemd/system/wg-easy.service → systemd unit definition
#
set -euo pipefail

# --- Prerequisite checks -----------------------------------------------------
for bin in docker htpasswd iptables systemctl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] Required command '$bin' not found in PATH"
    exit 1
  fi
done

# --- Constants ---------------------------------------------------------------
ENV_DIR="/etc/wg-easy"
ENV_FILE="$ENV_DIR/wg-easy.env"
WG_VOLUME="/var/lib/wg-easy"
LAN_IFACE="bridge0"
WG_SUBNET="10.7.0.0/24"
LAN_SUBNET="192.168.50.0/24"
SERVICE_FILE="/etc/systemd/system/wg-easy.service"
DEPLOYED_SCRIPT="/usr/local/bin/run-wg-easy.sh"
SCRIPT_VERSION="v2.2"

# --- Argument parsing --------------------------------------------------------
MODE="deploy"
if [[ "${1:-}" == "--remove" ]]; then
  MODE="remove"
elif [[ "${1:-}" == "--reset-password" ]]; then
  MODE="reset-password"
elif [[ "${1:-}" == "--check" ]]; then
  MODE="check"
fi

# --- REMOVE MODE -------------------------------------------------------------
if [[ "$MODE" == "remove" ]]; then
  echo "[INFO] Removing wg-easy deployment..."

  docker stop wg-easy >/dev/null 2>&1 || true
  docker rm wg-easy >/dev/null 2>&1 || true

  if iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -o "$LAN_IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -D POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -o "$LAN_IFACE" -j MASQUERADE
    echo "[INFO] Removed NAT rule for $WG_SUBNET → $LAN_SUBNET"
  fi

  rm -f "$ENV_FILE"    # password wg-easy
  #rm -rf "$WG_VOLUME"  #client configurations

  if [[ -f "$SERVICE_FILE" ]]; then
    systemctl stop wg-easy.service || true
    systemctl disable wg-easy.service || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reexec
    echo "[INFO] Removed systemd unit $SERVICE_FILE"
  fi

  if [[ -f "$DEPLOYED_SCRIPT" ]]; then
    rm -f "$DEPLOYED_SCRIPT"
    echo "[INFO] Removed deployed script $DEPLOYED_SCRIPT"
  fi

  echo "[INFO] wg-easy removal completed"
  exit 0
fi

# --- RESET-PASSWORD MODE -----------------------------------------------------
if [[ "$MODE" == "reset-password" ]]; then
  echo "[INFO] Resetting wg-easy admin password..."

  read -s -p "Enter new admin password for wg-easy: " PASSWORD1
  echo
  read -s -p "Confirm new password: " PASSWORD2
  echo

  if [ "$PASSWORD1" != "$PASSWORD2" ]; then
    echo "[ERROR] Passwords do not match"
    exit 1
  fi

  HASH=$(htpasswd -nbBC 10 "" "$PASSWORD1" | tr -d ':\n')

  mkdir -p "$ENV_DIR"
  chmod 700 "$ENV_DIR"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  if grep -q "^PASSWORD_HASH=" "$ENV_FILE"; then
    sed -i "s|^PASSWORD_HASH=.*|PASSWORD_HASH=$HASH|" "$ENV_FILE"
    echo "[INFO] Updated PASSWORD_HASH in $ENV_FILE"
  else
    echo "PASSWORD_HASH=$HASH" >> "$ENV_FILE"
    echo "[INFO] Added PASSWORD_HASH to $ENV_FILE"
  fi

  systemctl restart wg-easy.service
  echo "[INFO] Restarted wg-easy.service with new password"
  exit 0
fi

# --- CHECK MODE --------------------------------------------------------------
if [[ "$MODE" == "check" ]]; then
  echo "[CHECK] wg-easy health report"

  OK_COUNT=0; WARN_COUNT=0; ERR_COUNT=0

  if [[ -f "$ENV_FILE" ]] && grep -q "^PASSWORD_HASH=" "$ENV_FILE"; then
    echo " [✔] Env file present at $ENV_FILE with PASSWORD_HASH"; ((OK_COUNT++))
  else
    echo " [✘] Env file missing or incomplete ($ENV_FILE)"; ((ERR_COUNT++))
  fi

  if iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -o "$LAN_IFACE" -j MASQUERADE 2>/dev/null; then
    echo " [✔] NAT rule present for $WG_SUBNET → $LAN_SUBNET via $LAN_IFACE"; ((OK_COUNT++))
  else
    echo " [!] NAT rule missing for $WG_SUBNET → $LAN_SUBNET"; ((WARN_COUNT++))
  fi

  if docker ps --format '{{.Names}}' | grep -q "^wg-easy$"; then
    echo " [✔] wg-easy container is running"; ((OK_COUNT++))
  else
    echo " [!] wg-easy container not running"; ((WARN_COUNT++))
  fi

  if systemctl is-active --quiet wg-easy.service; then
    echo " [✔] wg-easy.service is active"; ((OK_COUNT++))
  else
    echo " [!] wg-easy.service is inactive"; ((WARN_COUNT++))
  fi

  echo " [ℹ] Last log entry:"
  journalctl -u wg-easy.service -n 1 --no-pager || echo " [!] No logs found"

  echo; echo "[SUMMARY] OK: $OK_COUNT, WARN: $WARN_COUNT, ERR: $ERR_COUNT"
  exit 0
fi

# --- Ensure deployed script is up-to-date ------------------------------------
if ! cmp -s "$0" "$DEPLOYED_SCRIPT"; then
  cp "$0" "$DEPLOYED_SCRIPT"
  chmod +x "$DEPLOYED_SCRIPT"
  echo "[INFO] Updated deployed script at $DEPLOYED_SCRIPT"
fi

# --- Ensure env directory and file exist -------------------------------------
mkdir -p "$ENV_DIR"
chmod 700 "$ENV_DIR"

if grep -q "^PASSWORD_HASH=" "$ENV_FILE" 2>/dev/null; then
  echo "[INFO] Using existing PASSWORD_HASH from $ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  read -s -p "Enter admin password for wg-easy: " PASSWORD1
  echo
  read -s -p "Confirm password: " PASSWORD2
  echo

  if [ "$PASSWORD1" != "$PASSWORD2" ]; then
    echo "[ERROR] Passwords do not match"
    exit 1
  fi

  HASH=$(htpasswd -nbBC 10 "" "$PASSWORD1" | tr -d ':\n')

  tee "$ENV_FILE" >/dev/null <<EOF
WG_HOST=nas.bardi.ch
WG_PORT=51822
WG_DEFAULT_ADDRESS=10.7.0.x
WG_DEFAULT_DNS=192.168.50.4
WG_ALLOWED_IPS=0.0.0.0/0,::/0,192.168.50.0/24
PASSWORD_HASH=$HASH
EOF
  chmod 600 "$ENV_FILE"
  echo "[INFO] Created $ENV_FILE with PASSWORD_HASH"
fi

# --- NAT rules for VPN clients -----------------------------------------------

# LAN access (VPN → LAN subnet)
if ! iptables -t nat -C POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -o "$LAN_IFACE" -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -s "$WG_SUBNET" -d "$LAN_SUBNET" -o "$LAN_IFACE" -j MASQUERADE
  echo "[INFO] Added NAT rule for $WG_SUBNET → $LAN_SUBNET via $LAN_IFACE"
else
  echo "[INFO] NAT rule already present for $WG_SUBNET → $LAN_SUBNET"
fi

# Internet access (VPN → WAN via default interface, excluding LAN)
WAN_IFACE=$(ip route | awk '/^default/ {print $5; exit}')
if ! iptables -t nat -C POSTROUTING -s "$WG_SUBNET" ! -d "$LAN_SUBNET" -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -s "$WG_SUBNET" ! -d "$LAN_SUBNET" -o "$WAN_IFACE" -j MASQUERADE
  echo "[INFO] Added NAT rule for $WG_SUBNET → Internet via $WAN_IFACE"
else
  echo "[INFO] NAT rule already present for $WG_SUBNET → Internet via $WAN_IFACE"
fi


# --- Ensure systemd unit exists ----------------------------------------------
SERVICE_CONTENT=$(cat <<EOF
[Unit]
Description=wg-easy VPN container
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker run -d \\
  --name=wg-easy \\
  --env-file=$ENV_FILE \\
  -v $WG_VOLUME:/etc/wireguard \\
  --network=host \\
  --cap-add=NET_ADMIN \\
  --cap-add=SYS_MODULE \\
  weejewel/wg-easy
ExecStop=/usr/bin/docker stop wg-easy
ExecStopPost=/usr/bin/docker rm wg-easy
ExecStartPost=/bin/bash -c 'echo "[INFO] wg-easy.service started run-wg-easy.sh $SCRIPT_VERSION at \$(date +"%Y-%m-%d %H:%M:%S")"'

[Install]
WantedBy=multi-user.target
EOF
)

if [[ ! -f "$SERVICE_FILE" ]] || ! cmp -s <(echo "$SERVICE_CONTENT") "$SERVICE_FILE"; then
  echo "$SERVICE_CONTENT" > "$SERVICE_FILE"
  systemctl daemon-reload
  systemctl enable wg-easy.service
  echo "[INFO] Installed/updated systemd unit at $SERVICE_FILE"
fi

# --- Ensure service is running -----------------------------------------------
if ! systemctl is-active --quiet wg-easy.service; then
  systemctl start wg-easy.service
  echo "[INFO] Started wg-easy.service"
else
  echo "[INFO] wg-easy.service already active"
fi

# --- Footer logging ----------------------------------------------------------
echo "[INFO] run-wg-easy.sh $SCRIPT_VERSION completed at $(date +"%Y-%m-%d %H:%M:%S")"