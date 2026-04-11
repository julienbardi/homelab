#!/bin/bash
# scripts/wg-down-router.sh
# Tear down WireGuard interface wgs1 on the router
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-down-router"

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-down-router.sh must be executed via the router control plane"
    exit 1
}

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

WG_IF="wgs1"

log "🛑 Tearing down router WireGuard interface ${WG_IF}"

# Tear down interface if present (router-side)
ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

if ip link show "${WG_IF}" >/dev/null 2>&1; then
    echo "[router-wg-down] Bringing interface down"
    ip link set "${WG_IF}" down || true

    echo "[router-wg-down] Deleting interface"
    ip link del "${WG_IF}" || true
else
    echo "[router-wg-down] Interface ${WG_IF} not present, nothing to do"
fi
EOF

log "✅ Router WireGuard interface ${WG_IF} is down"
