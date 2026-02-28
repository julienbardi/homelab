#!/bin/bash
#
# router-install-ca.sh
#
# Install homelab CA public certificate onto the router.
#
# Source (NAS):  /var/lib/ssl/canonical/ca.cer
# Dest (router): /jffs/ssl/certs/homelab_bardi_CA.pem
#

set -eu
# shellcheck disable=SC1091
source /usr/local/bin/common.sh

[ "${CALLED_BY_ROUTER_SYNC_SCRIPTS:-}" = "1" ] || {
    echo "❌ router-install-ca.sh must be executed via router-sync-scripts.sh"
    exit 1
}

CA_SRC="/var/lib/ssl/canonical/ca.cer"
CA_DST="/jffs/ssl/certs/homelab_bardi_CA.pem"

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

log "🔐 Publishing homelab CA to router"

[ "$(id -u)" -eq 0 ] || { echo "❌ Must be run as root"; exit 1; }
[ -f "$CA_SRC" ] || { echo "❌ CA source missing: $CA_SRC"; exit 1; }

require_file "$CA_SRC"

atomic_install \
    "$CA_SRC" \
    "$CA_DST" \
    "root:root" \
    "0644" \
    "$ROUTER_HOST" \
    "$ROUTER_SSH_PORT"

echo "✅ CA installed on router"
