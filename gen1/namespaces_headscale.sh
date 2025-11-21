#!/bin/bash
# ============================================================
# namespaces_headscale.sh
# ------------------------------------------------------------
# Generation 1 script: provision Headscale namespaces
# Host: 10.89.12.4 (NAS / VPN node)
# Responsibilities:
#   - Ensure baseline namespaces exist:
#       * bardi-family (trusted devices, full access)
#       * bardi-guests (restricted devices, relay-only)
#   - Detect extra namespaces and suggest cleanup commit messages
#   - Log all actions with timestamps and syslog integration
# ============================================================

set -euo pipefail

LOG_FILE="/var/log/namespaces_headscale.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [namespaces_headscale] $*" | tee -a "${LOG_FILE}"
    logger -t namespaces_headscale "$*"
}

BASE_NAMESPACES=("bardi-family" "bardi-guests")

# --- Namespace provisioning ---
log "Ensuring baseline namespaces exist..."
existing=$(sudo headscale namespaces list | awk '{print $2}' | tail -n +2)

for ns in "${BASE_NAMESPACES[@]}"; do
    if echo "$existing" | grep -q "^$ns$"; then
        log "OK: Namespace $ns already exists"
    else
        log "NEW: Creating namespace $ns"
        sudo headscale namespaces create "$ns"
        log "HINT: Commit message -> feat(headscale): add namespace ${ns}"
    fi
done

# --- Detect extras ---
for ns in $existing; do
    if [[ ! " ${BASE_NAMESPACES[*]} " =~ " $ns " ]]; then
        log "WARN: Extra namespace detected: $ns"
        log "HINT: Commit message -> chore(headscale): remove unused namespace ${ns}"
    fi
done

log "Namespace setup complete."
