#!/bin/bash
# scripts/wg-down-nas.sh
# Tear down all NAS WireGuard interfaces
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-down-nas"

[ "${NAS_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-down-nas.sh must be executed via the NAS control plane"
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"

log "🛑 Tearing down NAS WireGuard interfaces"

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

# --- Tear down each interface ------------------------------------------------

for iface in "${NAS_IFACES[@]}"; do
    log "🔧 Tearing down ${iface}"

    if ip link show "${iface}" >/dev/null 2>&1; then
        log "   Bringing interface down"
        run_as_root ip link set "${iface}" down || true

        log "   Deleting interface"
        run_as_root ip link del "${iface}" || true
    else
        log "⚪ Interface ${iface} not present"
    fi
done

log "✅ NAS WireGuard interfaces are down"
