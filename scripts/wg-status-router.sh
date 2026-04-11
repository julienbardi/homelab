#!/bin/bash
# scripts/wg-status-router.sh
# Show status of all router WireGuard interfaces
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-status-router"

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-status-router.sh must be executed via the router control plane"
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

log "📡 Querying router WireGuard status"

# --- Determine router interfaces --------------------------------------------

mapfile -t ROUTER_IFACES < <(
    awk -F'\t' '
        $1 !~ /^#/ && $1 != "iface" && $2 == "router" && $7 == "1" { print $1 }
    ' "${INPUT_DIR}/wg-interfaces.tsv"
)

if [[ ${#ROUTER_IFACES[@]} -eq 0 ]]; then
    log "No router interfaces found in wg-interfaces.tsv"
    exit 0
fi

# --- Execute status check on router -----------------------------------------

ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

for IFACE in ${ROUTER_IFACES[*]}; do
    echo ""
    echo "=== Router WireGuard Status (\$IFACE) ==="

    # Interface presence
    if ip link show "\$IFACE" >/dev/null 2>&1; then
        echo "Interface: PRESENT"
    else
        echo "Interface: NOT PRESENT"
        continue
    fi

    # Link state
    STATE=\$(ip link show "\$IFACE" | awk '/state/ {print \$9}')
    echo "State: \${STATE:-unknown}"

    # IP addresses
    IPV4=\$(ip -4 addr show "\$IFACE" | awk '/inet / {print \$2}')
    IPV6=\$(ip -6 addr show "\$IFACE" | awk '/inet6 / {print \$2}')
    echo "IPv4: \${IPV4:-none}"
    echo "IPv6: \${IPV6:-none}"

    # wg peer info
    echo "--- wg show ---"
    wg show "\$IFACE" || echo "wg show failed"

    echo "=== End (\$IFACE) ==="
done
EOF

log "📡 Router WireGuard status complete"
