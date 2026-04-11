#!/bin/bash
# scripts/wg-firewall-router.sh
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-firewall-router"

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ wg-firewall-router.sh must be executed via the router control plane"
    exit 1
}

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

FW_SCRIPT="/jffs/scripts/wgs1-firewall.sh"

log "🔥 Applying router firewall rules for wgs1"

# Validate script exists remotely
ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" \
    "[ -x '${FW_SCRIPT}' ]" \
    || { log "❌ Missing or non-executable firewall script: ${FW_SCRIPT}"; exit 1; }

# Execute firewall script remotely
ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" \
    "${FW_SCRIPT} up"

log "✅ Router firewall rules applied"
