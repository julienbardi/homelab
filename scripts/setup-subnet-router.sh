#!/bin/bash
# ============================================================
# setup-subnet-router.sh
# ------------------------------------------------------------
# Supporting script: configure subnet router
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Detect LAN conflicts (exclude Docker subnets if detected)
#   - Configure NAT and dnsmasq restart
#   - Apply GRO tuning for performance
#   - Auto-increment version number on each deploy
#   - Echo footer with version + timestamp for auditability
# ============================================================

set -euo pipefail

SCRIPT_NAME="setup-subnet-router.sh"
SCRIPT_PATH="/usr/local/bin/${SCRIPT_NAME}"
STATE_FILE="/var/lib/subnet-router.version"
LAN_IF="eth0"
LAN_SUBNET="10.89.12.0/24"
DOCKER_SUBNET="172.17.0.0/16"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a /var/log/${SCRIPT_NAME}.log
    logger -t ${SCRIPT_NAME} "$*"
}

# --- Version auto-increment ---
if [ ! -f "${STATE_FILE}" ]; then
    echo "1.0" > "${STATE_FILE}"
fi
CURRENT_VERSION=$(cat "${STATE_FILE}")
NEXT_VERSION=$(echo "${CURRENT_VERSION}" | awk -F. '{print $1 "." $2+1}')
echo "${NEXT_VERSION}" > "${STATE_FILE}"

# --- Conflict detection ---
log "Checking for subnet conflicts..."
if ip route show | grep -q "${DOCKER_SUBNET}"; then
    log "WARN: Docker subnet ${DOCKER_SUBNET} detected, excluding from routing"
    EXCLUDE_SUBNET="--exclude ${DOCKER_SUBNET}"
else
    EXCLUDE_SUBNET=""
fi

# --- NAT setup ---
log "Applying NAT rules..."
iptables-legacy -t nat -A POSTROUTING -s ${LAN_SUBNET} -o ${LAN_IF} -j MASQUERADE || log "ERROR: Failed to apply NAT"

# --- dnsmasq restart ---
log "Restarting dnsmasq..."
systemctl restart dnsmasq || log "ERROR: Failed to restart dnsmasq"

# --- GRO tuning ---
log "Applying GRO tuning..."
ethtool -K ${LAN_IF} gro off || log "WARN: Failed to disable GRO on ${LAN_IF}"

# --- Footer logging ---
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
log "Subnet router setup complete. Version ${NEXT_VERSION}, deployed at ${TIMESTAMP}."

