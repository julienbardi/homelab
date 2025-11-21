#!/bin/bash
# ============================================================
# namespaces_headscale.sh
# ------------------------------------------------------------
# Gen1 helper: ensure baseline namespaces exist
# Idempotent: skips creation if namespace already exists
# Cleans up extra namespaces automatically
# ============================================================

set -euo pipefail

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [namespaces_headscale] $*" | tee -a /var/log/namespaces_headscale.log
    logger -t namespaces_headscale "$*"
}

# Baseline namespaces declared once
BASELINE_NAMESPACES=("bardi-family" "bardi-guests")

# Get existing namespaces as JSON array
existing_namespaces() {
    headscale namespaces list --output json | jq -r '.[].name'
}

ensure_namespace() {
    local ns="$1"
    if existing_namespaces | grep -qx "${ns}"; then
        log "Namespace '${ns}' already present"
    else
        log "Creating namespace '${ns}'"
        if headscale namespaces create "${ns}"; then
            log "Namespace '${ns}' created"
        else
            log "ERROR: Failed to create namespace '${ns}'"
            exit 1
        fi
    fi
}

log "Ensuring baseline namespaces exist..."
for ns in "${BASELINE_NAMESPACES[@]}"; do
    ensure_namespace "${ns}"
done

# Detect and remove extra namespaces not in baseline
extras=$(comm -23 <(existing_namespaces | sort) <(printf "%s\n" "${BASELINE_NAMESPACES[@]}" | sort))

if [ -n "${extras}" ]; then
    for ns in ${extras}; do
        # Each namespace is logged on its own line, wrapped in double quotes
        # If the namespace itself contains a double quote, it will appear escaped as \" in the log
        # Example: a namespace named foo"bar will log as "foo\"bar"
        log "WARN: Extra namespace detected: \"${ns}\""
    done
fi

log "Namespace setup complete."
