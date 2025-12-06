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
LOGFILE="/var/log/wg_baseline.log"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [wg_baseline] $*" | tee -a "${LOGFILE}"
	logger -t wg_baseline "$*"
}

# --- Generate server keys ---
log "Generating WireGuard server keys..."
mkdir -p "${WG_DIR}"
umask 077

# Generate keys if missing; do not fail the whole script if keygen fails (log instead)
if [ ! -f "${WG_DIR}/server_private.key" ] || [ ! -f "${WG_DIR}/server_public.key" ]; then
	if ! wg genkey | tee "${WG_DIR}/server_private.key" | wg pubkey > "${WG_DIR}/server_public.key"; then
		log "ERROR: Failed to generate server keys"
	else
		chmod 600 "${WG_DIR}/server_private.key" "${WG_DIR}/server_public.key" || true
		log "Server keys generated and permissions set"
	fi
else
	log "Server keys already exist, skipping generation"
	chmod 600 "${WG_DIR}/server_private.key" "${WG_DIR}/server_public.key" || true
fi

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
chmod 600 "${WG_DIR}/${WG_IF}.conf" || true

# --- Create client template ---
CLIENT_NAME="${1:-}"
if [ -z "${CLIENT_NAME}" ]; then
	log "WARN: No client name provided, skipping client config"
else
	log "Generating client config for ${CLIENT_NAME}..."
	CLIENT_PRIV=$(wg genkey)
	CLIENT_PUB=$(echo "${CLIENT_PRIV}" | wg pubkey)

	# Write base client config (omit AllowedIPs here; append conditionally)
	cat > "${WG_DIR}/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = 10.4.0.2/32
DNS = ${SERVER_ADDR}

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${PORT}
PersistentKeepalive = 25
EOF

	# Only append AllowedIPs if VPN_SUBNET is set and non-empty
	if [ -n "${VPN_SUBNET:-}" ]; then
		printf "AllowedIPs = %s\n" "${VPN_SUBNET}" >> "${WG_DIR}/${CLIENT_NAME}.conf"
	fi

	# Secure the client config
	chmod 600 "${WG_DIR}/${CLIENT_NAME}.conf" || true

	# --- Generate QR code ---
	mkdir -p "${QR_DIR}"
	if command -v qrencode >/dev/null 2>&1; then
		log "Generating QR code for ${CLIENT_NAME}..."
		if ! qrencode -t ANSIUTF8 < "${WG_DIR}/${CLIENT_NAME}.conf" > "${QR_DIR}/${CLIENT_NAME}.qr"; then
			log "ERROR: Failed to generate QR code for ${CLIENT_NAME}"
		else
			chmod 600 "${QR_DIR}/${CLIENT_NAME}.qr" || true
		fi
	else
		log "WARN: qrencode not installed, skipping QR code generation"
	fi

	log "Client config written → ${WG_DIR}/${CLIENT_NAME}.conf"
fi

log "WireGuard baseline setup complete."
