#!/bin/bash
# ============================================================
# caddy-reload.sh
# ------------------------------------------------------------
# Generation 2 helper: safely reload Caddy
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Validate Caddyfile syntax before reload
#   - Reload Caddy service directly via caddy reload
#   - Log QUIC/HTTP/3 status
#   - Timeout guard to avoid hangs
#   - Exit non-zero if reload fails
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

SERVICE_NAME="caddy"
CADDYFILE="/etc/caddy/Caddyfile"

# --- Validate config ---
log "Validating Caddyfile at ${CADDYFILE}..."
if ! caddy validate --config "${CADDYFILE}" 2>&1 | tee -a "${LOG_FILE}"; then
	log "ERROR: Invalid Caddyfile syntax, aborting reload"
	exit 1
fi

# --- Reload service ---
log "Reloading Caddy service..."
if timeout 10 sudo caddy reload --config "${CADDYFILE}" --force; then
	log "OK: Caddy reloaded successfully via caddy reload"
else
	log "ERROR: Reload timed out or failed, continuing degraded"
	exit 1
fi

# --- QUIC/HTTP3 status ---
log "Checking QUIC/HTTP/3 support..."
if caddy list-modules | grep -Eq "http3|http.handlers.http3"; then
	log "QUIC/HTTP/3 module present"
else
	log "WARN: QUIC/HTTP/3 module not present"
fi

# --- Footer ---
log "Caddy reload complete."
