#!/bin/bash
# ============================================================
# tailnet.sh
# ------------------------------------------------------------
# Manage Headscale tailnet (namespace + device registration)
# ============================================================

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

HEADSCALE_BIN="/usr/local/bin/headscale"
NAMESPACE="family"
CONFIG_DIR="/etc/headscale"
QR_DIR="${CONFIG_DIR}/qr"

# ------------------------------------------------------------
# Ensure namespace exists
# ------------------------------------------------------------
log "ℹ️ Ensuring namespace '${NAMESPACE}' exists"

if ! ${HEADSCALE_BIN} namespaces list | grep -q "^${NAMESPACE}$"; then
    log "🔁 Creating namespace '${NAMESPACE}'"
    if ! ${HEADSCALE_BIN} namespaces create "${NAMESPACE}"; then
        log "❌ Failed to create namespace '${NAMESPACE}' — continuing degraded"
    fi
else
    log "ℹ️ Namespace '${NAMESPACE}' already exists"
fi

# ------------------------------------------------------------
# Validate device name
# ------------------------------------------------------------
DEVICE_NAME="${1:-}"

if [[ -z "${DEVICE_NAME}" ]]; then
    log "❌ No device name provided"
    echo "Usage: $0 <device-name>" >&2
    exit 1
fi

# ------------------------------------------------------------
# Register device
# ------------------------------------------------------------
log "🔁 Registering device '${DEVICE_NAME}' in namespace '${NAMESPACE}'"

if ! ${HEADSCALE_BIN} nodes register --namespace "${NAMESPACE}" --name "${DEVICE_NAME}"; then
    log "❌ Failed to register device '${DEVICE_NAME}' — continuing degraded"
else
    log "ℹ️ Device '${DEVICE_NAME}' registered"
fi

# ------------------------------------------------------------
# Generate client config
# ------------------------------------------------------------
log "🔁 Generating client config for '${DEVICE_NAME}'"

mkdir -p "${CONFIG_DIR}"
if ! ${HEADSCALE_BIN} nodes generate --namespace "${NAMESPACE}" --name "${DEVICE_NAME}" \
        > "${CONFIG_DIR}/${DEVICE_NAME}.conf"; then
    log "❌ Failed to generate config for '${DEVICE_NAME}'"
else
    log "ℹ️ Config written to ${CONFIG_DIR}/${DEVICE_NAME}.conf"
fi

# ------------------------------------------------------------
# Generate QR code
# ------------------------------------------------------------
if command -v qrencode >/dev/null 2>&1; then
    mkdir -p "${QR_DIR}"
    log "🔁 Generating QR code for '${DEVICE_NAME}'"
    if ! qrencode -t ANSIUTF8 < "${CONFIG_DIR}/${DEVICE_NAME}.conf" \
            > "${QR_DIR}/${DEVICE_NAME}.qr"; then
        log "❌ Failed to generate QR code for '${DEVICE_NAME}'"
    else
        log "ℹ️ QR code saved to ${QR_DIR}/${DEVICE_NAME}.qr"
    fi
else
    log "⚠️ qrencode not installed — skipping QR generation"
fi

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------
log "✅ Tailnet setup complete for device '${DEVICE_NAME}'"
