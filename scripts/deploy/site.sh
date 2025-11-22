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

SCRIPT_NAME=$(basename "$0" .sh)
touch /var/log/${SCRIPT_NAME}.log
chmod 644 /var/log/${SCRIPT_NAME}.log

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a /var/log/${SCRIPT_NAME}.log
	logger -t ${SCRIPT_NAME} "$*"
}

SRC_FILE="scripts/deploy/index.html"
DEST_FILE="/var/www/html/index.html"

log "Starting site deployment..."
if [ -f "$SRC_FILE" ]; then
	cp "$SRC_FILE" "$DEST_FILE"
	log "Copied $SRC_FILE to $DEST_FILE"
else
	log "ERROR: Source file $SRC_FILE not found"
	exit 1
fi

# Allow override via environment variable SERVICES
# Default list if not provided
: "${SERVICES:=caddy nginx apache2 lighttpd traefik}"

reloaded=false
for svc in $SERVICES; do
    if systemctl is-active --quiet "$svc"; then
        systemctl reload "$svc" || { log "ERROR: Failed to reload $svc"; exit 1; }
        log "Reloaded $svc service"
        reloaded=true
    fi
done

if [ "$reloaded" = false ]; then
    log "No web service detected to reload"
fi

log "Site deployment complete."
