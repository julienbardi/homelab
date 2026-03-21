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

[ "${ROUTER_CONTROL_PLANE:-}" = "1" ] || {
    echo "❌ router-install-ca.sh must be executed via the router control plane"
    echo "   (make router-converge or a router-* target)"
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

/usr/local/bin/install_file_if_changed_v2.sh -q \
    "" "" "$CA_SRC" \
    "$ROUTER_HOST" "$ROUTER_SSH_PORT" "$CA_DST" \
    root root 0644

echo "✅ CA installed on router"
