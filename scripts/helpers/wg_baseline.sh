#!/bin/bash
# ============================================================
# wg_baseline.sh
# ------------------------------------------------------------
# Generation 1 helper: generate baseline WireGuard config
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Generate fresh server private/public keys
#   - Create baseline server config (wg0.conf)
#   - Create client template configs
#   - Generate QR codes for mobile clients
#   - Log degraded mode if keygen or config fails
# ============================================================

set -euo pipefail

WG_DIR="/etc/wireguard"
WG_IF="wg0"
SERVER_IP="10.89.12.4"
VPN_SUBNET="10.4.0.0/24"
SERVER_ADDR="10.4.0.1"
PORT="51420"
QR_DIR="${WG_DIR}/qr"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [wg_baseline] $*" | tee -a /var/log/wg_baseline.log
    logger -t wg_baseline "$*"
}

# --- Generate server keys ---
log "Generating WireGuard server keys..."
mkdir -p "${WG_DIR}"
umask 077
wg genkey | tee "${WG_DIR}/server_private.key" | wg pubkey > "${WG_DIR}/server_public.key" || log "ERROR: Failed to generate server keys"

SERVER_PRIV=$(cat "${WG_DIR}/server_private.key")
SERVER_PUB=$(cat "${WG_DIR}/server_public.key")

# --- Create baseline server config ---
log "Creating baseline server config at ${WG_DIR}/${WG_IF}.conf..."
cat > "${WG_DIR}/${WG_IF}.conf" <<EOF
[Interface]
Address = ${SERVER_ADDR}/24
ListenPort = ${PORT}
PrivateKey = ${SERVER_PRIV}

# NAT and firewall rules applied separately via wg_firewall_apply.sh
EOF

# --- Create client template ---
CLIENT_NAME="$1"
if [ -z "${CLIENT_NAME}" ]; then
    log "WARN: No client name provided, skipping client config"
else
    log "Generating client config for ${CLIENT_NAME}..."
    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "${CLIENT_PRIV}" | wg pubkey)

    cat > "${WG_DIR}/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = 10.4.0.2/24
DNS = ${SERVER_ADDR}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${PORT}
AllowedIPs = ${VPN_SUBNET}
PersistentKeepalive = 25
EOF

    # --- Generate QR code ---
    mkdir -p "${QR_DIR}"
    if command -v qrencode >/dev/null 2>&1; then
        log "Generating QR code for ${CLIENT_NAME}..."
        echo "[Interface]" > "${QR_DIR}/${CLIENT_NAME}.qr"
        qrencode -t ANSIUTF8 < "${WG_DIR}/${CLIENT_NAME}.conf" >> "${QR_DIR}/${CLIENT_NAME}.qr" || log "ERROR: Failed to generate QR code"
    else
        log "WARN: qrencode not installed, skipping QR code generation"
    fi
fi

log "WireGuard baseline setup complete."
