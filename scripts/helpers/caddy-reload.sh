#!/bin/bash
# ============================================================
# caddy-reload.sh
# ------------------------------------------------------------
# Generation 2 helper: safely reload Caddy
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Validate Caddyfile syntax before reload
#   - Reload Caddy service via caddy reload (fallback: systemctl)
#   - Log QUIC/HTTP/3 status
#   - Timeout guard to avoid hangs
#   - Exit non-zero if reload fails
# ============================================================

set -euo pipefail
SCRIPT_NAME="caddy-reload"

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

CADDYFILE="/etc/caddy/Caddyfile"
SRC_CADDYFILE="/home/julie/src/homelab/config/caddy/Caddyfile"

# ------------------------------------------------------------
# Deploy updated Caddyfile
# ------------------------------------------------------------
log "🔁 Installing updated Caddyfile to ${CADDYFILE}"
run_as_root install -m 0644 -o root -g root "${SRC_CADDYFILE}" "${CADDYFILE}"

# ------------------------------------------------------------
# Validate config
# ------------------------------------------------------------
log "🔎 Validating Caddyfile at ${CADDYFILE}"

out=$( { sudo caddy validate --config "${CADDYFILE}" 2>&1; echo "EXIT:$?"; } )
status=$(printf '%s\n' "$out" | tail -n1 | cut -d: -f2)
out=$(printf '%s\n' "$out" | sed '$d')

while IFS= read -r line; do
    log "ℹ️ ${line}"
done <<< "${out}"

if [[ $status -ne 0 ]]; then
    log "❌ Caddyfile validation failed"
    log "⚠️ Edit ${SRC_CADDYFILE} and run 'make caddy' again"
    exit 1
else
    log "✅ Caddyfile validated"
fi

# ------------------------------------------------------------
# Reload service
# ------------------------------------------------------------
log "🔄 Reloading Caddy service via 'caddy reload'"

if run_as_root timeout 10 caddy reload --config "${CADDYFILE}" --force; then
    log "✅ Caddy reloaded successfully"
else
    log "⚠️ caddy reload failed — attempting systemctl reload"
    if run_as_root systemctl reload caddy; then
        log "✅ Caddy reloaded via systemctl"
    else
        log "❌ Reload failed completely"
        exit 1
    fi
fi

# ------------------------------------------------------------
# QUIC / HTTP/3 status
# ------------------------------------------------------------
log "🔎 Checking QUIC/HTTP/3 support"

if run_as_root caddy list-modules | grep -Eq "http3|http.handlers.http3"; then
    log "ℹ️ QUIC/HTTP/3 module present"
else
    log "⚠️ QUIC/HTTP/3 module not present"
fi

# ------------------------------------------------------------
# Footer
# ------------------------------------------------------------
log "ℹ️ Caddy version: $(caddy version)"
log "✅ Reload complete"
