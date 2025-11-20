#!/bin/bash
# ============================================================
# setup_coredns.sh
# ------------------------------------------------------------
# Generation 0 script: install and configure CoreDNS
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Install CoreDNS binary
#   - Generate Corefile with Headscale DNS plugin enabled
#   - Forward all non-tailnet queries to Unbound (10.89.12.4:53)
#   - Create systemd unit for CoreDNS
#   - Log degraded mode if Unbound is unreachable
# ============================================================

set -euo pipefail

SERVICE_NAME="coredns"
CONFIG_DIR="/etc/coredns"
CONFIG_FILE="${CONFIG_DIR}/Corefile"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
NAS_IP="10.89.12.4"
UNBOUND_IP="${NAS_IP}"   # Unbound runs locally on NAS
TAILNET_DOMAIN="tailnet"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [setup_coredns] $*" | tee -a /var/log/setup_coredns.log
    logger -t setup_coredns "$*"
}

# --- Prerequisite checks ---
log "Checking prerequisites..."
if ! command -v coredns >/dev/null 2>&1; then
    log "WARN: CoreDNS not found, attempting install..."
    curl -L https://github.com/coredns/coredns/releases/latest/download/coredns_$(uname -s)_$(uname -m).tgz \
        -o /tmp/coredns.tgz || log "ERROR: CoreDNS download failed, continuing degraded"
    tar -xzf /tmp/coredns.tgz -C /usr/local/bin || log "ERROR: CoreDNS install failed, continuing degraded"
fi

# --- Check Unbound reachability ---
if ! nc -z ${UNBOUND_IP} 53 >/dev/null 2>&1; then
    log "WARN: Unbound (${UNBOUND_IP}:53) unreachable, CoreDNS will run in degraded mode"
fi

# --- Generate Corefile ---
log "Generating CoreDNS Corefile at ${CONFIG_FILE}..."
mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_FILE}" <<EOF
.${TAILNET_DOMAIN}:53 {
    headscale {
        base_domain ${TAILNET_DOMAIN}
        listen ${NAS_IP}:53
    }
    log
    errors
}

.:53 {
    forward . ${UNBOUND_IP}:53
    cache 30
    log
    errors
}
EOF

# --- Systemd unit ---
log "Creating systemd unit at ${SYSTEMD_UNIT}..."
cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=CoreDNS server for tailnet + Unbound forwarding
After=network.target

[Service]
ExecStart=/usr/local/bin/coredns -conf ${CONFIG_FILE}
WorkingDirectory=${CONFIG_DIR}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to start CoreDNS, continuing degraded"

log "CoreDNS setup complete (listening on ${NAS_IP}:53, forwarding to Unbound ${UNBOUND_IP}:53)."
