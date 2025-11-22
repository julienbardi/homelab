#!/bin/bash
# ============================================================
# setup-subnet-router.sh
# ------------------------------------------------------------
# Supporting script: configure subnet router
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Detect conflicts against *all* current IPv4/IPv6 subnets
#   - Configure NAT (idempotent)
#   - Apply GRO tuning for performance
#   - Define firewall rules for DNS/SSH/Web UI (idempotent)
#   - Persist firewall rules safely
#   - Echo footer for auditability
# Note:
#   LAN_IF must be set to bridge0 (bridge interface) for correct routing.
#   DNS resolver reload (Unbound) is not handled here.
# ============================================================

set -euo pipefail

LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"

SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a "${LOG_FILE}"
    logger -t "${SCRIPT_NAME}" "$*"
}

# Idempotent rule inserter: checks with -C first
ensure_rule() {
    # usage: ensure_rule iptables-legacy -I INPUT -p tcp --dport 2222 -j ACCEPT
    local cmd="$1"; shift
    local args=("$@")
    if $cmd -C "${args[@]}" 2>/dev/null; then
        log "Rule already present: $cmd ${args[*]}"
    else
        $cmd "${args[@]}"
        log "Rule added: $cmd ${args[*]}"
    fi
}

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
    log "ERROR: Interface ${LAN_IF} not found or not UP, aborting."
    exit 1
fi

# --- Conflict detection (audit only) ---
log "Checking for subnet conflicts..."
conflicts=""
for route in $(ip -4 route show | awk '{print $1}'; ip -6 route show | awk '{print $1}'); do
    conflicts="${conflicts}${route},"
done
if [ -n "${conflicts}" ]; then
    conflicts="${conflicts%,}"  # trim trailing comma
    log "WARN: Existing subnets detected: ${conflicts}"
else
    log "No existing subnets detected."
fi

# --- NAT setup (idempotent) ---
log "Ensuring NAT MASQUERADE for ${LAN_SUBNET} via ${LAN_IF}..."
iptables-legacy -t nat -C POSTROUTING -s "${LAN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE 2>/dev/null || \
iptables-legacy -t nat -A POSTROUTING -s "${LAN_SUBNET}" -o "${LAN_IF}" -j MASQUERADE
log "NAT MASQUERADE ensured."

# --- Firewall rules for essential services (idempotent) ---
log "Ensuring firewall INPUT rules for DNS/SSH/Web UI..."
# DNS (Unbound)
ensure_rule iptables-legacy -I INPUT -p udp --dport 53 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 53 -j ACCEPT
# SSH (custom port and standard port)
ensure_rule iptables-legacy -I INPUT -p tcp --dport 2222 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 22   -j ACCEPT
# UGOS Pro Web UI (nginx)
ensure_rule iptables-legacy -I INPUT -p tcp --dport 9999 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 9443 -j ACCEPT
# UPnP service
ensure_rule iptables-legacy -I INPUT -p tcp --dport 49152 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 49152 -j ACCEPT
# wsdd2 service (Web Services Discovery)
ensure_rule iptables-legacy -I INPUT -p udp --dport 3702 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 5355 -j ACCEPT
# SMB file sharing
ensure_rule iptables-legacy -I INPUT -p tcp --dport 137 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 137 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 138 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 138 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 139 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 139 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p tcp --dport 445 -j ACCEPT
ensure_rule iptables-legacy -I INPUT -p udp --dport 445 -j ACCEPT

# --- GRO tuning ---
log "Applying GRO tuning..."
if ethtool -K "${LAN_IF}" gro off 2>/dev/null; then
    log "GRO disabled on ${LAN_IF}"
else
    log "WARN: Failed to disable GRO on ${LAN_IF}"
fi

# --- Persist firewall rules ---
log "Persisting iptables rules to /etc/iptables/rules.v4 and /etc/iptables/rules.v6..."
if iptables-legacy-save > /etc/iptables/rules.v4 && ip6tables-legacy-save > /etc/iptables/rules.v6; then
    log "Firewall rules persisted."
else
    log "ERROR: Failed to persist firewall rules!"
fi

# Inform about netfilter-persistent status (for restore on reboot)
if systemctl is-enabled netfilter-persistent >/dev/null 2>&1; then
    log "netfilter-persistent is enabled; rules will restore on boot."
else
    log "WARN: netfilter-persistent is NOT enabled."
    log "Enable with: sudo apt-get install -y netfilter-persistent && sudo systemctl enable --now netfilter-persistent"
fi

# --- Footer logging ---
COMMIT_HASH=$(git -C ~/src/homelab rev-parse --short HEAD 2>/dev/null || echo "unknown")
log "Subnet router setup complete. Commit=${COMMIT_HASH}, Timestamp=$(date '+%Y-%m-%d %H:%M:%S')"