#!/bin/bash
# ============================================================
# tailnet.sh
# ------------------------------------------------------------
# Manage Headscale tailnet (namespace + device registration)
# ============================================================

set -euo pipefail
SCRIPT_NAME="tailnet"
source "/home/julie/src/homelab/scripts/common.sh"

HEADSCALE_BIN="/usr/local/bin/headscale"
NAMESPACE="family"
CONFIG_DIR="/etc/headscale"
QR_DIR="${CONFIG_DIR}/qr"

# --- Ensure namespace exists ---
log "Ensuring namespace '${NAMESPACE}' exists..."
if ! ${HEADSCALE_BIN} namespaces list | grep -q "${NAMESPACE}"; then
    ${HEADSCALE_BIN} namespaces create ${NAMESPACE} || log "ERROR: Failed to create namespace ${NAMESPACE}, continuing degraded"
else
    log "Namespace ${NAMESPACE} already exists"
fi

# --- Register device ---
DEVICE_NAME="${1:-}"
if [[ -z "${DEVICE_NAME}" ]]; then
    log "ERROR: No device name provided"
    echo "Usage: $0 <device-name>" >&2
    exit 1
fi

log "Registering device '${DEVICE_NAME}' in namespace '${NAMESPACE}'..."
if ! ${HEADSCALE_BIN} nodes register --user "${NAMESPACE}" --name "${DEVICE_NAME}"; then
    log "ERROR: Failed to register device ${DEVICE_NAME}, continuing degraded"
else
    log "Device ${DEVICE_NAME} registered successfully"
fi

# --- Generate client config ---
log "Generating client config for ${DEVICE_NAME}..."
mkdir -p "${QR_DIR}"
${HEADSCALE_BIN} nodes generate --namespace "${NAMESPACE}" --name "${DEVICE_NAME}" > "${CONFIG_DIR}/${DEVICE_NAME}.conf" || log "ERROR: Failed to generate config"

# --- Generate QR code ---
if command -v qrencode >/dev/null 2>&1; then
    log "Generating QR code for ${DEVICE_NAME}..."
    qrencode -t ANSIUTF8 < "${CONFIG_DIR}/${DEVICE_NAME}.conf" > "${QR_DIR}/${DEVICE_NAME}.qr" || log "ERROR: Failed to generate QR code"
else
    log "WARN: qrencode not installed, skipping QR code generation"
fi

log "Tailnet setup complete for device ${DEVICE_NAME}."
