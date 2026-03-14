#!/bin/bash
# certs-create.sh — CA generation for homelab_bardi
# Uses shared common.sh for logging and safety
set -euo pipefail

# --- MINIMALIST LOGGING ---
# Setting this to empty tells common.sh to suppress the [certs-deploy] prefix
SCRIPT_NAME=""

# Sourcing the COMMON to provide the install_files_if_changed_v2 function
COMMON="/usr/local/bin/common.sh"
[[ -f "$COMMON" ]] || { echo "❌ Error: $COMMON not found" >&2; exit 1; }
# shellcheck source=scripts/common.sh
source "$COMMON"

CA_KEY="/etc/ssl/private/ca/homelab_bardi_CA.key"
CA_PUB="/etc/ssl/certs/homelab_bardi_CA.pem"

# Root check
if [[ "$(id -u)" -ne 0 ]]; then
    log "❌ This script must be run as root (use sudo)"
    exit 1
fi

#log "🛡️ Checking CA private key + public cert existence..."

if [[ -f "$CA_KEY" ]] && [[ -f "$CA_PUB" ]]; then
    log "⚪ CA already exists: $CA_PUB"
else
    log "⚙️ Initializing CA directory structure..."
    mkdir -p /etc/ssl/private/ca
    chmod 700 /etc/ssl/private/ca

    log "🔑 Generating EC P-384 private key..."
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out "$CA_KEY"
    chmod 0600 "$CA_KEY"

    log "📜 Generating CA public cert..."
    # Standard P-384 CA with Basic Constraints and Key Usage extensions
    openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 3650 \
        -subj "/CN=homelab-bardi-CA/O=bardi.ch/OU=homelab" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign" \
        -out "$CA_PUB"

    chmod 0644 "$CA_PUB"
    log "✅ CA created successfully: $CA_PUB"
fi