#!/bin/bash
# ============================================================
# router_audit.sh
# ------------------------------------------------------------
# Audit health of VPN + DNS stack
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Summarize Headscale, Unbound, ndppd services
#   - Summarize WireGuard interfaces wg0-wg7 and tailscale0
#   - Check firewall rules (run_as_root /sbin/iptables-legacy)
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

VPN_SUBNET="10.4.0.0/24"
SCRIPT_NAME=$(basename "$0" .sh)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*"
    logger -t "${SCRIPT_NAME}" "$*"
}

# --- Service Summary Table ---
log "üîç Service summary"

SERVICES=(headscale unbound ndppd)

# Header
printf "%-12s %-8s %-8s %-40s\n" "Service" "Active" "Enabled" "Hint"

for svc in "${SERVICES[@]}"; do
    active="'"å"
    enabled="unknown"
    hint="-"

    if systemctl is-active --quiet "${svc}"; then
        active="'"Ö"
    fi

    enabled=$(systemctl is-enabled "${svc}" 2>/dev/null || echo "unknown")

    if [[ "${active}" == "'"å" ]]; then
        if [[ "${enabled}" == "enabled" ]]; then
            hint="check logs: journalctl -u ${svc}"
        else
            hint="run 'systemctl enable --now ${svc}'"
        fi
    fi

    printf "%-12s %-8s %-8s %-40s\n" "${svc}" "${active}" "${enabled}" "${hint}"
done

# --- VPN Interface Summary Table ---
log "üîç VPN interface summary"

IFACES=(wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7 tailscale0)

# Header
printf "%-12s" "Interface"
for IFACE in "${IFACES[@]}"; do printf "%-12s" "${IFACE}"; done
echo

# Present
printf "%-12s" "Present"
for IFACE in "${IFACES[@]}"; do
    if ip link show "${IFACE}" >/dev/null 2>&1; then printf "%-12s" "'"Ö"; else printf "%-12s" "'"å"; fi
done
echo

# Configured
printf "%-12s" "Configured"
for IFACE in "${IFACES[@]}"; do
    if [[ "${IFACE}" == "tailscale0" ]]; then printf "%-12s" "'ÑπÔ∏è"; continue; fi
    wg_output=$(run_as_root /usr/bin/wg show "${IFACE}" 2>/dev/null || true)
    if echo "${wg_output}" | grep -q "peer:"; then printf "%-12s" "'"Ö"; else printf "%-12s" "'ö Ô∏è"; fi
done
echo

# Peer status (first 3 peers)
for peer_idx in 1 2 3; do
    printf "%-12s" "Peer #${peer_idx}"
    for IFACE in "${IFACES[@]}"; do
        if [[ "${IFACE}" == "tailscale0" ]]; then printf "%-12s" ""; continue; fi
        wg_output=$(run_as_root /usr/bin/wg show "${IFACE}" 2>/dev/null || true)
        peer_line=$(echo "${wg_output}" | awk '/peer:/ {print}' | sed -n "${peer_idx}p")
        if [[ -n "${peer_line}" ]]; then
            handshake=$(echo "${wg_output}" | awk '/latest handshake:/ {print}' | sed -n "${peer_idx}p")
            if [[ -n "${handshake}" && ! "${handshake}" =~ "ago" ]]; then
                printf "%-12s" "'ö Ô∏è"
            else
                printf "%-12s" "'"Ö"
            fi
        else
            printf "%-12s" ""
        fi
    done
    echo
done

# --- Firewall ---
log "üîç Checking firewall rules..."
if run_as_root /sbin/iptables-legacy -L INPUT >/dev/null 2>&1; then
    if run_as_root /sbin/iptables-legacy -L INPUT | grep -q "${VPN_SUBNET}"; then
        log "'"Ö Firewall rules include VPN subnet ${VPN_SUBNET}"
    else
        log "'ö Ô∏è WARN: Firewall rules missing VPN subnet ${VPN_SUBNET}"
    fi
else
    log "'"å ERROR: run_as_root /sbin/iptables-legacy not available"
fi

log "üèÅ Router audit complete"
