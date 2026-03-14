#!/bin/bash
# /usr/local/bin/certs-deploy.sh
set -euo pipefail

# --- MINIMALIST LOGGING ---
# Setting this to empty tells common.sh to suppress the [certs-deploy] prefix
SCRIPT_NAME=""

# Sourcing the COMMON to provide the install_files_if_changed_v2 function
COMMON="/usr/local/bin/common.sh"
[[ -f "$COMMON" ]] || { echo "❌ Error: $COMMON not found" >&2; exit 1; }
# shellcheck source=scripts/common.sh
source "$COMMON"

# Constants
CA_PUB="/etc/ssl/certs/homelab_bardi_CA.pem"
CANON_CA="/var/lib/ssl/canonical/ca.cer"
CADDY_CA="/etc/ssl/caddy/homelab_bardi_CA.pem"
ACME_HOME="/var/lib/acme"
ACME_GROUP="ssl-cert"

# 1. Environment Hardening (Replaces Makefile fix-acme-perms)
if [ -d "$ACME_HOME" ]; then
    log "🔧 Hardening ACME permissions at $ACME_HOME"
    # Ensure group exists and set ownership
    chown -R root:"$ACME_GROUP" "$ACME_HOME"

    # Secure directories
    find "$ACME_HOME" -type d -exec chmod 750 {} +

    # Secure sensitive keys
    find "$ACME_HOME" -type f -name "*.key" -exec chmod 600 {} + 2>/dev/null

    # Set public readability for certificates and configs
    find "$ACME_HOME" -type f \( -name "*.cer" -o -name "*.conf" -o -name "*.csr" \) -exec chmod 644 {} + 2>/dev/null

    # Ensure scripts are executable but protected
    find "$ACME_HOME" -type f -name "*.sh" -exec chmod 750 {} + 2>/dev/null
fi

# 2. Synchronization Logic
require_file "$CA_PUB"
#log "🛡️  Synchronizing CA public certs..."

ANY_CHANGED=0

# Use the V2 engine for atomic, hash-based deployment
install_files_if_changed_v2 ANY_CHANGED \
    "" "" "$CA_PUB"   "" "" "$CANON_CA" "root" "root" "0644" \
    "" "" "$CANON_CA" "" "" "$CADDY_CA" "root" "root" "0644"

if [[ "$ANY_CHANGED" -eq 1 ]]; then
    log "✅ CA public cert updated and deployed"
else
    log "⚪ CA public cert already up-to-date"
fi