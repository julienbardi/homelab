#!/bin/bash
# ============================================================
# site.sh
# ------------------------------------------------------------
# Deployment script for site artifacts
# Responsibilities:
#   - Copy index.html into /var/www/html
#   - Reload web service if available
#   - Log all actions to /var/log/site.log and syslog
# ============================================================

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

SRC_FILE="/home/julie/src/homelab/scripts/deploy/index.html"
DEST_FILE="/var/www/html/index.html"

log "Starting site deployment..."

if [ -f "$SRC_FILE" ]; then
    run_as_root cp "${SRC_FILE}" "${DEST_FILE}"
    log "Copied $SRC_FILE to $DEST_FILE"
else
    log "ERROR: Source file $SRC_FILE not found"
    exit 1
fi

: "${SERVICES:=caddy nginx apache2 lighttpd traefik}"

reloaded=false
for svc in ${SERVICES}; do
    if systemctl is-active --quiet "${svc}"; then
        if run_as_root systemctl reload "${svc}"; then
            log "Reloaded ${svc} service"
            reloaded=true
        else
            log "ERROR: Failed to reload ${svc}"
            exit 1
        fi
    fi
done

if [ "${reloaded}" = false ]; then
    log "No active web service detected to reload"
fi

COMMIT_HASH=$(git -C "/home/julie/src/homelab" rev-parse --short HEAD 2>/dev/null || echo "unknown")
log "Site deployment complete. Commit=${COMMIT_HASH}"
