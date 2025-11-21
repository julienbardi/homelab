#!/bin/bash
# ============================================================
# namespaces_headscale.sh
# ------------------------------------------------------------
# Gen1 helper: ensure baseline namespaces exist
# Idempotent: skips creation if namespace already exists
# ============================================================

set -euo pipefail

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [namespaces_headscale] $*" | tee -a /var/log/namespaces_headscale.log
    logger -t namespaces_headscale "$*"
}

# Baseline namespaces declared once
BASELINE_NAMESPACES=("bardi-family" "bardi-guests")

ensure_namespace() {
    local ns="$1"
    if headscale namespaces list | awk '{print $1}' | grep -qx "${ns}"; then
        log "Namespace ${ns} already exists, skipping"
    else
        log "NEW: Creating namespace ${ns}"
        if headscale namespaces create "${ns}"; then
            log "Namespace ${ns} created successfully"
            log "HINT: Commit message -> feat(headscale): add namespace ${ns}"
        else
            log "ERROR: Failed to create namespace ${ns}"
            exit 1
        fi
    fi
}

log "Ensuring baseline namespaces exist..."
for ns in "${BASELINE_NAMESPACES[@]}"; do
    ensure_namespace "${ns}"
done

# Detect extra namespaces not in baseline
extras=$(headscale namespaces list | awk '{print $1}' | grep -vxF "${BASELINE_NAMESPACES[@]}" || true)

if [ -n "${extras}" ]; then
    log "WARN: Extra namespace(s) detected: ${extras}"
    log "HINT: Commit message -> chore(headscale): remove unused namespace(s)"
fi

log "Namespace setup complete."
