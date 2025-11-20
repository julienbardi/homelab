#!/bin/bash
# ============================================================
# setup_headscale.sh
# ------------------------------------------------------------
# Generation 0 script: install and configure Headscale
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Install prerequisites (Go, SQLite/Postgres, WireGuard kernel module)
#   - Generate headscale.yaml config with DNS plugin enabled
#   - Create systemd unit for Headscale
#   - Log degraded mode if dependencies are unreachable
# ============================================================

set -euo pipefail

SERVICE_NAME="headscale"
CONFIG_DIR="/etc/headscale"
CONFIG_FILE="${CONFIG_DIR}/headscale.yaml"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
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

# --- Generate config ---
log "Generating Headscale config at ${CONFIG_FILE}..."
mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_FILE}" <<EOF
server_url: http://${NAS_IP}:8080
listen_addr: 0.0.0.0:8080
private_key_path: ${CONFIG_DIR}/private.key
db_type: sqlite
db_path: ${CONFIG_DIR}/db.sqlite
dns:
  base_domain: tailnet
  nameservers:
    - ${NAS_IP}   # CoreDNS will run here
EOF

# --- Noise private key generation (Headscale v0.27+ requirement) ---
if [ ! -f /etc/headscale/noise_private.key ]; then
    echo "$(date +'%F %T') [setup_headscale] Generating Noise private key..."
    headscale generate noise-key -o /etc/headscale/noise_private.key
    if [ $? -eq 0 ]; then
        echo "$(date +'%F %T') [setup_headscale] Noise private key created at /etc/headscale/noise_private.key"
    else
        echo "$(date +'%F %T') [setup_headscale] ERROR: Failed to generate Noise private key" >&2
    fi
else
    echo "$(date +'%F %T') [setup_headscale] Noise private key already exists, skipping generation"
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to start Headscale, continuing degraded"

log "Headscale setup complete (version $(headscale version 2>/dev/null || echo 'unknown'))."
