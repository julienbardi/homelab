#!/bin/bash
# ============================================================
# rotate-unbound-rootkeys.sh
# ------------------------------------------------------------
# Generation 1 helper: refresh DNSSEC trust anchors for Unbound
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Run unbound-anchor to refresh root trust anchors
#   - Validate updated keys
#   - Restart Unbound service if anchors changed
#   - Log degraded mode if refresh fails
# ============================================================

set -euo pipefail

SERVICE_NAME="unbound"
TRUST_ANCHORS="/var/lib/unbound/root.key"
LOGFILE="/var/log/rotate-unbound-rootkeys.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [rotate-unbound-rootkeys] $*" | tee -a ${LOGFILE}
    logger -t rotate-unbound-rootkeys "$*"
}

# --- Refresh trust anchors ---
log "Refreshing DNSSEC trust anchors..."
if unbound-anchor -a ${TRUST_ANCHORS}; then
    log "OK: Trust anchors refreshed at ${TRUST_ANCHORS}"
else
    log "ERROR: Failed to refresh trust anchors, continuing degraded"
fi

# --- Validate anchors ---
log "Validating trust anchors..."
if grep -q "DS" ${TRUST_ANCHORS}; then
    log "Trust anchors contain DS records (valid)"
else
    log "WARN: Trust anchors missing DS records"
fi

# --- Restart Unbound ---
log "Restarting Unbound service..."
if systemctl restart ${SERVICE_NAME}; then
    log "OK: Unbound restarted successfully"
else
    log "ERROR: Failed to restart Unbound, continuing degraded"
fi

log "Trust anchor rotation complete."
