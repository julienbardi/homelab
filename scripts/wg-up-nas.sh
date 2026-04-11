#!/bin/bash
# scripts/wg-up-nas.sh
# Bring up all NAS WireGuard interfaces
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-up-nas"

[ "${NAS_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-up-nas.sh must be executed via the NAS control plane"
    echo "   (make nas-converge or a nas-* target)"
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"

log "🚀 Bringing up NAS WireGuard interfaces"

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

# --- Bring up each interface -------------------------------------------------

for iface in "${NAS_IFACES[@]}"; do
    WG_CONF="/etc/wireguard/${iface}.conf"

    require_file "${WG_CONF}"

    log "🔧 Bringing up ${iface}"

    # Tear down stale interface
    if ip link show "${iface}" >/dev/null 2>&1; then
        log "   Tearing down stale ${iface}"
        run_as_root ip link set "${iface}" down || true
        run_as_root ip link del "${iface}" || true
    fi

    # Create interface
    run_as_root ip link add "${iface}" type wireguard

    # Apply config
    run_as_root wg setconf "${iface}" "${WG_CONF}"

    # Apply Address= manually (wg-quick does this, wg setconf does NOT)
    ADDR_LINE=$(grep '^Address' "${WG_CONF}" | cut -d'=' -f2 | tr -d ' ')
    for addr in $ADDR_LINE; do
        run_as_root ip address add "$addr" dev "${iface}"
    done

    # Bring interface up
    run_as_root ip link set "${iface}" up

    log "   ${iface} is up"
done

log "✅ NAS WireGuard interfaces are up"
