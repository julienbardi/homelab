#!/bin/bash
# ============================================================
# namespaces_headscale.sh
# ------------------------------------------------------------
# Gen1 helper: ensure baseline namespaces exist
# Idempotent: skips creation if namespace already exists
# Detects and reports extra namespaces
# ============================================================

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

# Baseline namespaces declared once
BASELINE_NAMESPACES=("bardi-family" "bardi-guests")

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

existing_namespaces() {
    headscale namespaces list --output json | jq -r '.[].name'
}

ensure_namespace() {
    local ns="$1"

    if existing_namespaces | grep -qx "${ns}"; then
        log "ℹ️ Namespace '${ns}' already present"
        return 0
    fi

    log "🔁 Creating namespace '${ns}'"
    if headscale namespaces create "${ns}"; then
        log "ℹ️ Namespace '${ns}' created"
    else
        log "❌ Failed to create namespace '${ns}'"
        exit 1
    fi
}

# ------------------------------------------------------------
# Ensure baseline namespaces exist
# ------------------------------------------------------------
log "ℹ️ Ensuring baseline namespaces exist"

for ns in "${BASELINE_NAMESPACES[@]}"; do
    ensure_namespace "${ns}"
done

# ------------------------------------------------------------
# Detect extra namespaces
# ------------------------------------------------------------
extras=$(comm -23 \
    <(existing_namespaces | sort) \
    <(printf "%s\n" "${BASELINE_NAMESPACES[@]}" | sort))

if [[ -n "${extras}" ]]; then
    while IFS= read -r ns; do
        [[ -z "$ns" ]] && continue
        log "⚠️ Extra namespace detected: '${ns}'"
    done <<< "${extras}"
else
    log "ℹ️ No extra namespaces detected"
fi

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------
log "✅ Namespace setup complete"
