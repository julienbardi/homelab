#!/bin/bash
# ============================================================
# setup_headscale.sh
# ------------------------------------------------------------
# Generation 0 script: install and configure Headscale
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Install prerequisites (Go, SQLite/Postgres, WireGuard kernel module)
#   - Deploy headscale.yaml from repo (config/headscale.yaml)
#   - Generate Noise private key if missing
#   - Create systemd unit for Headscale
#   - Log degraded mode if dependencies are unreachable
# ============================================================

set -euo pipefail

SERVICE_NAME="headscale"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="${CONFIG_DIR}/headscale.yaml"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
REPO_CONFIG="/home/julie/src/homelab/config/headscale.yaml"
NAS_IP="10.89.12.4"
ROUTER_IP="10.89.12.1"
UNBOUND_IP="${NAS_IP}"   # Unbound runs locally on NAS

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [setup_headscale] $*" | tee -a /var/log/setup_headscale.log
    logger -t setup_headscale "$*"
}

# --- Prerequisite checks ---
log "Checking prerequisites..."
if ! command -v go >/dev/null 2>&1; then
    log "WARN: Go runtime not found, attempting install..."
    apt-get update && apt-get install -y golang || log "ERROR: Go install failed, continuing degraded"
fi

if ! modprobe wireguard >/dev/null 2>&1; then
    log "ERROR: WireGuard kernel module missing, continuing degraded"
fi

# --- Install Headscale ---
log "Installing Headscale..."
if ! command -v headscale >/dev/null 2>&1; then
    go install github.com/juanfont/headscale/cmd/headscale@latest || log "ERROR: Headscale install failed, continuing degraded"
fi

# --- Deploy config from repo ---
log "Deploying Headscale config from ${REPO_CONFIG} to ${CONFIG_FILE}..."
mkdir -p "${CONFIG_DIR}"
cp "${REPO_CONFIG}" "${CONFIG_FILE}"

# --- Noise private key generation (Headscale v0.27+ requirement) ---
if [ ! -f "${CONFIG_DIR}/noise_private.key" ]; then
    log "Generating Noise private key..."
    headscale generate noise-key -o "${CONFIG_DIR}/noise_private.key"
    if [ $? -eq 0 ]; then
        log "Noise private key created at ${CONFIG_DIR}/noise_private.key"
    else
        log "ERROR: Failed to generate Noise private key"
    fi
else
    log "Noise private key already exists, skipping generation"
fi

# --- Ensure database file exists with correct permissions ---
log "Ensuring database file exists with correct ownership and permissions..."
if [ ! -f /etc/headscale/db.sqlite ]; then
    touch /etc/headscale/db.sqlite
fi

# Ownership
chown headscale:headscale /etc/headscale/db.sqlite
chown headscale:headscale /etc/headscale

# Permissions
chmod 660 /etc/headscale/db.sqlite
chmod 770 /etc/headscale

# Clean up stale SQLite lock/journal files
rm -f /etc/headscale/db.sqlite-*

# --- Systemd unit ---
log "Creating systemd unit at ${SYSTEMD_UNIT}..."
cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=Headscale coordination server
After=network.target

[Service]
ExecStart=$(which headscale) serve
WorkingDirectory=${CONFIG_DIR}
Restart=always
Environment=HEADSCALE_CONFIG=${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to start Headscale, continuing degraded"

log "Headscale setup complete (version $(headscale version 2>/dev/null || echo 'unknown'))."
