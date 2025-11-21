#!/bin/bash
# ============================================================
# setup-subnet-router.sh
# ------------------------------------------------------------
# Supporting script: configure subnet router
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Detect conflicts against *all* current IPv4/IPv6 subnets
#   - Configure NAT
#   - Apply GRO tuning for performance
#   - Auto-increment version number on each deploy
#   - Echo footer with version + timestamp for auditability
# Note:
#   DNS resolver reload (Unbound) is not handled here.
#   It should be declared as a dependency in the Makefile or dns_setup.sh
#   for consistency across orchestration.
# ============================================================

set -euo pipefail

SCRIPT_NAME="setup-subnet-router.sh"
SCRIPT_PATH="/usr/local/bin/${SCRIPT_NAME}"
STATE_FILE="/var/lib/subnet-router.version"
LAN_IF="eth0"
LAN_SUBNET="10.89.12.0/24"

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
# Detect conflicts against *all* current IPv4 and IPv6 routes.
# Safe: if IPv6 not configured, no matches are produced.
log "Checking for subnet conflicts..."
conflicts=""

for route in $(ip -4 route show | awk '{print $1}'; ip -6 route show | awk '{print $1}'); do
    conflicts="${conflicts}${route},"
done

if [ -n "${conflicts}" ]; then
    conflicts="${conflicts%,}"  # trim trailing comma
    log "WARN: Existing subnets detected: ${conflicts}"
    EXCLUDE_SUBNET="--exclude ${conflicts}"
else
    EXCLUDE_SUBNET=""
fi

# --- NAT setup ---
log "Applying NAT rules..."
iptables-legacy -t nat -A POSTROUTING -s "${LAN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE || log "ERROR: Failed to apply NAT"

# --- GRO tuning ---
log "Applying GRO tuning..."
ethtool -K "${LAN_IF}" gro off || log "WARN: Failed to disable GRO on ${LAN_IF}"

# --- Footer logging ---
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
log "Subnet router setup complete. Version ${NEXT_VERSION}, deployed at ${TIMESTAMP}."
