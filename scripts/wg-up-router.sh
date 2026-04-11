#!/bin/bash
# scripts/wg-up-router.sh
# Bring up WireGuard interface wgs1 on the router
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-up-router"

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-up-router.sh must be executed via the router control plane"
    echo "   (make router-converge or a router-* target)"
    exit 1
}

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

WG_IF="wgs1"
WG_CONF="/jffs/etc/wireguard/${WG_IF}.conf"

log "🚀 Bringing up WireGuard interface ${WG_IF} on router"

# The entire bring-up happens *on the router*, not locally.
ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

echo "[router-wg-up] Using config: ${WG_CONF}"

if [ ! -f "${WG_CONF}" ]; then
    echo "❌ Missing router WireGuard config: ${WG_CONF}" >&2
    exit 1
fi

# Tear down stale interface if present
if ip link show "${WG_IF}" >/dev/null 2>&1; then
    ip link set "${WG_IF}" down || true
    ip link del "${WG_IF}" || true
fi

# Create + configure
ip link add "${WG_IF}" type wireguard
wg setconf "${WG_IF}" "${WG_CONF}"

# BusyBox does NOT apply Address= from config → apply manually
ADDR_LINE=\$(grep '^Address' "${WG_CONF}" | cut -d'=' -f2 | tr -d ' ')
for addr in \$ADDR_LINE; do
    ip address add "\$addr" dev "${WG_IF}"
done

# Bring interface up
ip link set "${WG_IF}" up

echo "[router-wg-up] Interface ${WG_IF} is up"
EOF

log "✅ Router WireGuard interface ${WG_IF} is up"
