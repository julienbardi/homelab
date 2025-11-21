#!/bin/bash
# ============================================================
# setup_headscale.sh
# ------------------------------------------------------------
# Generation 0 script: install and configure Headscale
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Install prerequisites (Go, SQLite/Postgres, WireGuard kernel module)
#   - Deploy headscale.yaml and derp.yaml from repo
#   - Generate Noise private key if missing
#   - Create systemd unit for Headscale
#   - Log degraded mode if dependencies are unreachable
# ============================================================

set -euo pipefail

SERVICE_NAME="headscale"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="${CONFIG_DIR}/headscale.yaml"
DERP_FILE="${CONFIG_DIR}/derp.yaml"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
REPO_CONFIG="/home/julie/src/homelab/config/headscale.yaml"
REPO_DERP="/home/julie/src/homelab/config/derp.yaml"
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

# --- Deploy configs from repo ---
log "Deploying Headscale config from ${REPO_CONFIG} to ${CONFIG_FILE}..."
mkdir -p "${CONFIG_DIR}"
cp "${REPO_CONFIG}" "${CONFIG_FILE}"

log "Deploying DERPMap config from ${REPO_DERP} to ${DERP_FILE}..."
cp "${REPO_DERP}" "${DERP_FILE}"

# --- Noise private key generation ---
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
if [ ! -f /var/lib/headscale/db.sqlite ]; then
    mkdir -p /var/lib/headscale
    touch /var/lib/headscale/db.sqlite
fi
chown headscale:headscale /var/lib/headscale/db.sqlite /var/lib/headscale
chmod 660 /var/lib/headscale/db.sqlite
chmod 770 /var/lib/headscale

# Clean up stale SQLite lock/journal files
rm -f /var/lib/headscale/db.sqlite-*

# --- Runtime directory and socket cleanup ---
log "Ensuring runtime directory and socket permissions..."
mkdir -p /var/run/headscale
chown headscale:headscale /var/run/headscale
chmod 770 /var/run/headscale
if [ -S /var/run/headscale/headscale.sock ]; then
    rm -f /var/run/headscale/headscale.sock
    log "Removed stale socket file /var/run/headscale/headscale.sock"
fi

# --- DERPMap configuration ---
log "Ensuring DERPMap file exists and is referenced in config..."

DERP_FILE="/etc/headscale/derp.yaml"

# Create DERPMap file if missing
if [ ! -f "${DERP_FILE}" ]; then
    cat > "${DERP_FILE}" <<EOF
regions:
  1:
    region_id: 1
    region_code: "global"
    region_name: "Tailscale Global DERPs"
    nodes:
      - name: "derp1"
        region_id: 1
        host_name: "derp1.tailscale.com"
        stun: true
      - name: "derp2"
        region_id: 1
        host_name: "derp2.tailscale.com"
        stun: true
EOF
    log "DERPMap file created at ${DERP_FILE}"
else
    log "DERPMap file already exists at ${DERP_FILE}, skipping creation"
fi

# Ensure headscale.yaml points to DERPMap file
if ! grep -q "derp:" "${CONFIG_FILE}"; then
    cat >> "${CONFIG_FILE}" <<EOF

derp:
  paths:
    - ${DERP_FILE}
EOF
    log "Added DERPMap reference to ${CONFIG_FILE}"
else
    log "DERPMap reference already present in ${CONFIG_FILE}"
fi

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
RuntimeDirectory=headscale
RuntimeDirectoryMode=0770

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to start Headscale, continuing degraded"

log "Headscale setup complete (version $(headscale version 2>/dev/null || echo 'unknown'))."
