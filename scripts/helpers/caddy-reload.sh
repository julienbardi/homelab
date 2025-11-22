#!/bin/bash
# ============================================================
# caddy-reload.sh
# ------------------------------------------------------------
# Generation 1 helper: safely reload Caddy
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Validate Caddyfile syntax before reload
#   - Reload Caddy service via systemd
#   - Log QUIC/HTTP/3 status
#   - Log degraded mode if reload fails
# ============================================================

set -euo pipefail

SERVICE_NAME="caddy"
CADDYFILE="/etc/caddy/Caddyfile"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [caddy-reload] $*" | tee -a /var/log/caddy-reload.log
    logger -t caddy-reload "$*"
}

# --- Validate config ---
log "Validating Caddyfile at ${CADDYFILE}..."
if ! caddy validate --config ${CADDYFILE} >/dev/null 2>&1; then
    log "ERROR: Invalid Caddyfile syntax, aborting reload"
    exit 1
fi

# --- Reload service ---
log "Reloading Caddy service..."
if systemctl reload ${SERVICE_NAME}; then
    log "OK: Caddy service reloaded successfully"
else
    log "ERROR: Failed to reload Caddy service, continuing degraded"
fi

# --- QUIC/HTTP3 status ---
log "Checking QUIC/HTTP/3 support..."
if caddy list-modules | grep -q "http.handlers.http3"; then
    log "QUIC/HTTP/3 module present"
else
    log "WARN: QUIC/HTTP/3 module not present"
fi

log "Caddy reload complete."
