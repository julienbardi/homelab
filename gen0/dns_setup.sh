#!/bin/bash
# ============================================================
# dns_setup.sh
# ------------------------------------------------------------
# Generation 0 script: validate and configure Unbound DNS
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Check Unbound service health
#   - Refresh DNSSEC trust anchors
#   - Restart Unbound if needed
#   - Log degraded mode if Unbound is unreachable
# ============================================================

set -euo pipefail

SERVICE_NAME="unbound"
UNBOUND_CONF="/etc/unbound/unbound.conf"
TRUST_ANCHORS="/var/lib/unbound/root.key"
NAS_IP="10.89.12.4"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [dns_setup] $*" | tee -a /var/log/dns_setup.log
    logger -t dns_setup "$*"
}

# --- Check Unbound service ---
log "Checking Unbound service..."
if ! systemctl is-active --quiet ${SERVICE_NAME}; then
    log "WARN: Unbound service not active, attempting restart..."
    systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to restart Unbound, continuing degraded"
fi

# --- Validate config syntax ---
log "Validating Unbound config..."
unbound-checkconf ${UNBOUND_CONF} || log "ERROR: Unbound config invalid, continuing degraded"

# --- Refresh DNSSEC trust anchors ---
log "Refreshing DNSSEC trust anchors..."
unbound-anchor -a ${TRUST_ANCHORS} || log "ERROR: Failed to refresh trust anchors, continuing degraded"

# --- Connectivity test ---
log "Testing DNS resolution via Unbound..."
if ! dig @${NAS_IP} . NS +short >/dev/null 2>&1; then
    log "ERROR: Unbound not resolving root NS records, continuing degraded"
else
    log "OK: Unbound resolving correctly"
fi

# --- Restart service to apply changes ---
log "Restarting Unbound service..."
systemctl restart ${SERVICE_NAME} || log "ERROR: Failed to restart Unbound after trust anchor refresh"

log "DNS setup complete (Unbound running on ${NAS_IP}:53)."
