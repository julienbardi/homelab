#!/bin/bash
# ============================================================
# dns-runtime-guard.sh
# ------------------------------------------------------------
# Health‑check script: validate Unbound runtime health
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Check Unbound service health
#   - Validate configuration syntax
#   - Verify resolver functionality
#   - Log degraded mode if Unbound is unreachable
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

SERVICE_NAME="unbound"
UNBOUND_CONF="/etc/unbound/unbound.conf"

# --- Check Unbound service ---
log "Checking Unbound service..."
if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "WARN: Unbound service not active, attempting restart..."
    run_as_root systemctl restart "${SERVICE_NAME}" || log "ERROR: Failed to restart Unbound, continuing degraded"
fi

# --- Validate config syntax ---
CONF_OUTPUT=$(timeout 10s unbound-checkconf "${UNBOUND_CONF}" 2>&1)
log "Unbound config check: ${CONF_OUTPUT}"

# --- Connectivity test ---
log "Testing DNS resolution via Unbound..."
if ! dig @127.0.0.1 -p 5335 . NS +short >/dev/null 2>&1; then
    log "ERROR: Unbound not resolving root NS records, continuing degraded"
else
    log "OK: Unbound resolving correctly"
fi

# --- Footer logging ---
COMMIT_HASH=$(git -C "/home/julie/src/homelab" rev-parse --short HEAD 2>/dev/null || echo "unknown")
log "DNS setup complete (dnsmasq → unbound @ 127.0.0.1:5335). Commit=${COMMIT_HASH}"
