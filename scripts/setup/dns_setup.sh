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

# Source shared helpers (log, run_as_root, ensure_rule)
source "${HOME}/src/homelab/scripts/common.sh"

SERVICE_NAME="unbound"
UNBOUND_CONF="/etc/unbound/unbound.conf"
TRUST_ANCHORS="/var/lib/unbound/root.key"
NAS_IP="10.89.12.4"

# --- Check Unbound service ---
log "Checking Unbound service..."
if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
	log "WARN: Unbound service not active, attempting restart..."
	run_as_root systemctl restart "${SERVICE_NAME}" || log "ERROR: Failed to restart Unbound, continuing degraded"
fi

# --- Validate config syntax ---
log "Validating Unbound config..."
if ! unbound-checkconf "${UNBOUND_CONF}"; then
	log "ERROR: Unbound config invalid, continuing degraded"
fi

# --- Refresh DNSSEC trust anchors ---
log "Refreshing DNSSEC trust anchors..."
if ! run_as_root unbound-anchor -a "${TRUST_ANCHORS}"; then
	log "ERROR: Failed to refresh trust anchors, continuing degraded"
fi

# --- Connectivity test ---
log "Testing DNS resolution via Unbound..."
if ! dig @"${NAS_IP}" . NS +short >/dev/null 2>&1; then
	log "ERROR: Unbound not resolving root NS records, continuing degraded"
else
	log "OK: Unbound resolving correctly"
fi

# --- Restart service to apply changes ---
log "Restarting Unbound service..."
if ! run_as_root systemctl restart "${SERVICE_NAME}"; then
	log "ERROR: Failed to restart Unbound after trust anchor refresh"
fi

# --- Footer logging ---
COMMIT_HASH=$(git -C "${HOME}/src/homelab" rev-parse --short HEAD 2>/dev/null || echo "unknown")
log "DNS setup complete (Unbound running on ${NAS_IP}:53). Commit=${COMMIT_HASH}, Timestamp=$(date '+%Y-%m-%d %H:%M:%S')"