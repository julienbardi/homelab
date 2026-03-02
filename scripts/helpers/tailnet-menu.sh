#!/bin/bash
# ============================================================
# tailnet-menu.sh
# ------------------------------------------------------------
# Interactive Headscale client management menu (amtm style)
# ============================================================

set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

HEADSCALE_BIN="/usr/local/bin/headscale"
NAMESPACES=("bardi-family" "bardi-guest")

# --- Ensure namespaces exist ---
for ns in "${NAMESPACES[@]}"; do
    if ! ${HEADSCALE_BIN} namespaces list | grep -q "^${ns}\$"; then
        log "🔁 Creating namespace ${ns}..."
        if ! ${HEADSCALE_BIN} namespaces create "${ns}"; then
            log "❌ Failed to create namespace ${ns}"
        fi
    fi
done

# --- Helper: validate namespace ---
validate_ns() {
    local ns="$1"
    for valid in "${NAMESPACES[@]}"; do
        if [[ "$ns" == "$valid" ]]; then
            return 0
        fi
    done
    log "❌ Invalid namespace: $ns"
    return 1
}

# --- Menu loop ---
while true; do
    log "ℹ️ ============================================================"
    log "ℹ️  Headscale Tailnet Menu"
    log "ℹ️ ============================================================"
    for ns in "${NAMESPACES[@]}"; do
        log "ℹ️ Namespace: ${ns}"
        ${HEADSCALE_BIN} nodes list --namespace "${ns}" 2>/dev/null | awk 'NR>1 {print "  - " $2}'
    done
    log "ℹ️ ------------------------------------------------------------"
    log "ℹ️ (n) Register new client"
    log "ℹ️ (r) Revoke client"
    log "ℹ️ (d) Display client config"
    log "ℹ️ (c) Display QR code"
    log "ℹ️ (e) Exit"
    log "ℹ️ ------------------------------------------------------------"
    read -rp "Select option: " choice

    case "$choice" in
        n|N)
            read -rp "Enter namespace [bardi-family/bardi-guest]: " ns
            validate_ns "$ns" || continue
            read -rp "Enter new client name: " device
            log "🔁 Registering ${device} in ${ns}..."
            if ! ${HEADSCALE_BIN} nodes register --namespace "${ns}" --name "${device}"; then
                log "❌ Failed to register ${device}"
            fi
            ;;
        r|R)
            read -rp "Enter namespace [bardi-family/bardi-guest]: " ns
            validate_ns "$ns" || continue
            read -rp "Enter client name to revoke: " device
            log "🔁 Revoking ${device} in ${ns}..."
            if ! ${HEADSCALE_BIN} nodes delete --namespace "${ns}" --name "${device}"; then
                log "❌ Failed to revoke ${device}"
            fi
            ;;
        d|D)
            read -rp "Enter namespace [bardi-family/bardi-guest]: " ns
            validate_ns "$ns" || continue
            read -rp "Enter client name to display config: " device
            log "🔁 Displaying config for ${device}..."
            if ! ${HEADSCALE_BIN} nodes generate --namespace "${ns}" --name "${device}" | tee "/etc/headscale/${device}.conf"; then
                log "❌ Failed to generate config for ${device}"
            fi
            ;;
        c|C)
            read -rp "Enter namespace [bardi-family/bardi-guest]: " ns
            validate_ns "$ns" || continue
            read -rp "Enter client name to display QR: " device
            if command -v qrencode >/dev/null 2>&1; then
                if ! ${HEADSCALE_BIN} nodes generate --namespace "${ns}" --name "${device}" | qrencode -t ANSIUTF8; then
                    log "❌ Failed to generate QR for ${device}"
                fi
            else
                log "⚠️ qrencode not installed, cannot display QR"
            fi
            ;;
        e|E)
            log "ℹ️ Exiting."
            exit 0
            ;;
        *)
            log "❌ Invalid choice."
            ;;
    esac
done
