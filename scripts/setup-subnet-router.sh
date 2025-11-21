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
#   - Echo footer for auditability
# Note:
#   LAN_IF must be set to br0 (bridge interface) for correct routing.
#   DNS resolver reload (Unbound) is not handled here.
# ============================================================

set -euo pipefail

SCRIPT_NAME="setup-subnet-router.sh"
LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a /var/log/${SCRIPT_NAME}.log
    logger -t ${SCRIPT_NAME} "$*"
}

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
    log "ERROR: Interface ${LAN_IF} not found or not UP, aborting NAT setup."
    exit 1
fi

# --- Conflict detection ---
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
log "Subnet router setup complete."
