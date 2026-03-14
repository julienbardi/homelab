#!/bin/bash
# /usr/local/bin/certs-deploy.sh
set -euo pipefail

SCRIPT_NAME=""
COMMON="/usr/local/bin/common.sh"
[[ -f "$COMMON" ]] || { echo "❌ Error: $COMMON not found" >&2; exit 1; }
source "$COMMON"

# Constants
CA_PUB="/etc/ssl/certs/homelab_bardi_CA.pem"
CANON_CA="/var/lib/ssl/canonical/ca.cer"
CADDY_CA="/etc/ssl/caddy/homelab_bardi_CA.pem"
ACME_HOME="/var/lib/acme"
ACME_GROUP="ssl-cert"
DOMAIN="bardi.ch"

# Caddy Target Paths
CADDY_CERT_DIR="/etc/ssl/caddy"
CADDY_CERT="$CADDY_CERT_DIR/$DOMAIN.cer"
CADDY_KEY="$CADDY_CERT_DIR/$DOMAIN.key"

# 1. Environment Hardening
if [ -d "$ACME_HOME" ]; then
    log "🔧 Hardening ACME permissions at $ACME_HOME"
    chown -R root:"$ACME_GROUP" "$ACME_HOME"
    find "$ACME_HOME" -type d -exec chmod 750 {} +
    find "$ACME_HOME" -type f -exec chmod 600 {} +
    find "$ACME_HOME" -name "*.sh" -exec chmod 750 {} +
fi

# 2. Synchronization Logic
require_file "$CA_PUB"
ANY_CHANGED=0

# Sync CA Public Certs
install_files_if_changed_v2 ANY_CHANGED \
    "" "" "$CA_PUB"   "" "" "$CANON_CA" "root" "root" "0644" \
    "" "" "$CANON_CA" "" "" "$CADDY_CA" "root" "root" "0644"

# Sync Site Certificates (Pushing ECC certs to Caddy)
SRC_DIR="$ACME_HOME/${DOMAIN}_ecc"
if [ -d "$SRC_DIR" ]; then
    log "📦 Deploying $DOMAIN ECC certificates to $CADDY_CERT_DIR"
    mkdir -p "$CADDY_CERT_DIR"

    # We use fullchain.cer for Caddy to ensure the intermediate is provided
    install_files_if_changed_v2 ANY_CHANGED \
        "" "" "$SRC_DIR/fullchain.cer" "" "" "$CADDY_CERT" "root" "root" "0644" \
        "" "" "$SRC_DIR/$DOMAIN.key"   "" "" "$CADDY_KEY"  "root" "root" "0600"
fi

# 3. Service Reload
if [[ "$ANY_CHANGED" -eq 1 ]]; then
    log "✅ Certificates updated and deployed"
    if systemctl is-active --quiet caddy; then
        log "🔄 Reloading Caddy..."
        systemctl reload caddy
    fi
else
    log "⚪ All certificates already up-to-date"
fi