#!/bin/bash
# scripts/wg-status-nas.sh
# Show status of all NAS WireGuard interfaces
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-status-nas"

[ "${NAS_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-status-nas.sh must be executed via the NAS control plane"
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"

log "📡 Querying NAS WireGuard status"

# --- Determine NAS interfaces ------------------------------------------------

mapfile -t NAS_IFACES < <(
    awk -F'\t' '
        $1 !~ /^#/ && $1 != "iface" && $2 == "nas" && $7 == "1" { print $1 }
    ' "${INPUT_DIR}/wg-interfaces.tsv"
)

if [[ ${#NAS_IFACES[@]} -eq 0 ]]; then
    log "No NAS interfaces found in wg-interfaces.tsv"
    exit 0
fi

# --- Status for each interface ----------------------------------------------

for iface in "${NAS_IFACES[@]}"; do
    WG_CONF="/etc/wireguard/${iface}.conf"

    echo ""
    echo "=== NAS WireGuard Status (${iface}) ==="

    # Interface presence
    if ip link show "${iface}" >/dev/null 2>&1; then
        echo "Interface: PRESENT"
    else
        echo "Interface: NOT PRESENT"
        continue
    fi

    # Link state
    STATE=$(ip link show "${iface}" | awk '/state/ {print $9}')
    echo "State: ${STATE:-unknown}"

    # IP addresses
    IPV4=$(ip -4 addr show "${iface}" | awk '/inet / {print $2}')
    IPV6=$(ip -6 addr show "${iface}" | awk '/inet6 / {print $2}')
    echo "IPv4: ${IPV4:-none}"
    echo "IPv6: ${IPV6:-none}"

    # wg peer info
    echo "--- wg show ---"
    wg show "${iface}" || echo "wg show failed"

    echo "=== End (${iface}) ==="
done

echo ""
log "📡 NAS WireGuard status complete"
