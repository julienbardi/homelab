#!/bin/bash
# ============================================================
# setup_coredns.sh
# ------------------------------------------------------------
# Install and configure CoreDNS with Headscale + Unbound
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Install CoreDNS binary
#   - Generate Corefile with Headscale DNS plugin enabled
#   - Forward all non-tailnet queries to Unbound (10.89.12.4:53)
#   - Create systemd unit for CoreDNS
#   - Log degraded mode if Unbound is unreachable
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

LOGFILE="/var/log/homelab/setup_coredns.log"

SERVICE_NAME="coredns"
CONFIG_DIR="/etc/coredns"
CONFIG_FILE="${CONFIG_DIR}/Corefile"
SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
NAS_IP="10.89.12.4"
UNBOUND_IP="${NAS_IP}"   # Unbound runs locally on NAS
TAILNET_DOMAIN="tailnet"

# --- Prerequisite checks ---
log "Checking prerequisites..."
if ! command -v coredns >/dev/null 2>&1; then
	log "WARN: CoreDNS not found, attempting install..."
	curl -L "https://github.com/coredns/coredns/releases/latest/download/coredns_$(uname -s)_$(uname -m).tgz" \
		-o "/tmp/coredns.tgz" || log "ERROR: CoreDNS download failed, continuing degraded"
	run_as_root tar -xzf "/tmp/coredns.tgz" -C "/usr/local/bin" || log "ERROR: CoreDNS install failed, continuing degraded"
fi

# --- Check Unbound reachability ---
if ! nc -z "${UNBOUND_IP}" 53 >/dev/null 2>&1; then
	log "WARN: Unbound (${UNBOUND_IP}:53) unreachable, CoreDNS will run in degraded mode"
fi

# --- Generate Corefile ---
log "Generating CoreDNS Corefile at ${CONFIG_FILE}..."
run_as_root mkdir -p "${CONFIG_DIR}"
run_as_root tee "${CONFIG_FILE}" > /dev/null <<EOF
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
run_as_root tee "${SYSTEMD_UNIT}" > /dev/null <<EOF
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

run_as_root systemctl daemon-reload
run_as_root systemctl enable "${SERVICE_NAME}"
run_as_root systemctl restart "${SERVICE_NAME}" || log "ERROR: Failed to start CoreDNS, continuing degraded"

if systemctl is-active --quiet "${SERVICE_NAME}"; then
	listeners=$(ss -ltnp 2>/dev/null | awk '/coredns/ {print $4}' | sort -u | paste -s -d',' -)
	[ -z "$$listeners" ] && listeners="(no listening sockets detected)"
	log "CoreDNS setup complete; listeners: $$listeners; forwarding non-tailnet queries to ${UNBOUND_IP}:53"
else
	log "CoreDNS setup finished but service is not active; check journalctl -u ${SERVICE_NAME}"
fi
