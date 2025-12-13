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

#SERVICE_NAME="caddy"
CADDYFILE="/etc/caddy/Caddyfile"

# --- Deploy updated Caddyfile ---
SRC_CADDYFILE="/home/julie/src/homelab/config/caddy/Caddyfile"
atomic_install "${SRC_CADDYFILE}" "${CADDYFILE}" root:root 0644

# --- Validate config ---
log "Validating Caddyfile at ${CADDYFILE}..."
out=$( { sudo caddy validate --config "${CADDYFILE}" 2>&1; echo "EXIT:$?"; } )
status=$(printf '%s\n' "$out" | tail -n1 | cut -d: -f2)
out=$(printf '%s\n' "$out" | sed '$d')

while IFS= read -r line; do
	log "DETAILS: ${line}"
done <<< "${out}"

if [[ $status -ne 0 ]]; then
	log "ERROR: caddy validate failed"
	log "ACTION: Edit ${SRC_CADDYFILE} and execute again 'make caddy'"
	exit 1
else
	log "SUCCESS: Caddyfile validated"
fi



# --- Reload service (use only for small changes else it hangs, user restart instead)---
log "Reloading Caddy service..."
if run_as_root timeout 10 caddy reload --config "${CADDYFILE}" --force; then
	log "OK: Caddy reloaded successfully via caddy reload"
else
	log "WARN: caddy reload failed, trying systemctl reload..."
	if run_as_root systemctl reload caddy; then
		log "OK: Caddy reloaded via systemctl"
	else
		log "ERROR: Reload failed completely"
		exit 1
	fi
fi

# --- QUIC/HTTP3 status ---
log "Checking QUIC/HTTP/3 support..."
if run_as_root caddy list-modules | grep -Eq "http3|http.handlers.http3"; then
	log "QUIC/HTTP/3 module present"
else
	log "WARN: QUIC/HTTP/3 module not present"
fi

# --- Footer ---
log "Caddy version: $(caddy version)"
log "Reload complete."

