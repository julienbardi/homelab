#!/bin/bash
# scripts/wg-install-router.sh
# Install wgs1.conf onto the router using IFC_v2
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-install-router"

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-install-router.sh must be executed via the router control plane"
    echo "   (make router-converge or a router-* target)"
    exit 1
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/output/router"

SRC_CONF="${OUTPUT_DIR}/wgs1.conf"
DST_PATH="/jffs/etc/wireguard/wgs1.conf"

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

OWNER="root"
GROUP="root"
MODE="0600"

log "📡 Installing WireGuard router config"
log "   SRC: ${SRC_CONF}"
log "   DST: ${DST_PATH}"

require_file "${SRC_CONF}"

changed=0
install_files_if_changed_v2 changed \
    "" "" "${SRC_CONF}" \
    "${ROUTER_HOST}" "${ROUTER_SSH_PORT}" "${DST_PATH}" \
    "${OWNER}" "${GROUP}" "${MODE}"

if [[ "$changed" -eq 1 ]]; then
    log "🚀 Router WireGuard config updated → ${DST_PATH}"
else
    log "⚪ Router WireGuard config already up-to-date"
fi
