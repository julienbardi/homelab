#!/usr/bin/env bash
set -euo pipefail

# --- Authoritative Context ---
# These are provided by export in mk/00_constants.mk
: "${ROUTER_HOST:?Missing ROUTER_HOST}"
: "${ROUTER_SSH_PORT:?Missing ROUTER_SSH_PORT}"
: "${ROUTER_WG_DIR:?Missing ROUTER_WG_DIR}"
: "${WG_ROOT:?Missing WG_ROOT}"

# Local paths for NAS/Server execution
NAS_WG_CONF="/etc/wireguard"
IFC_BIN="/usr/local/bin/install_file_if_changed_v2.sh"
PEER_MAP="${WG_ROOT}/output/peer-map.tsv"

# Swapped to match Makefile: wgctl.sh [TARGET] [MODE]
TARGET="${1:-}"
MODE="${2:-status}"

log() { echo "[$TARGET] $1"; }

# --- Actions ---

do_install() {
    log "Initiating atomic IFC installation..."

    if [[ "$TARGET" == "router" ]]; then
        # Deployment from NAS output -> Router JFFS
        for conf in "${WG_ROOT}/output/router"/*.conf; do
            [[ -e "$conf" ]] || continue
            # IFC: SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE
            "$IFC_BIN" "" "22" "$conf" \
                       "$ROUTER_ADDR" "$ROUTER_SSH_PORT" "${ROUTER_WG_DIR}/$(basename "$conf")" \
                       "0" "0" "0600"
        done
    elif [[ "$TARGET" == "nas" ]]; then
        # Deployment from NAS output -> NAS /etc/wireguard
        for conf in "${WG_ROOT}/output/server"/*.conf; do
            [[ -e "$conf" ]] || continue
            "$IFC_BIN" "" "22" "$conf" \
                       "" "22" "${NAS_WG_CONF}/$(basename "$conf")" \
                       "0" "0" "0600"
        done
    fi
}

do_up() {
    log "Bringing up interfaces..."
    if [[ "$TARGET" == "router" ]]; then
        # Merlin uses wg-quick via Entware or custom shell wrapper
        ssh -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" \
            "for f in ${ROUTER_WG_DIR}/*.conf; do wg-quick up \"\$f\" 2>/dev/null || true; done"
    else
        for f in "${NAS_WG_CONF}"/*.conf; do
            sudo wg-quick up "$f" 2>/dev/null || true
        done
    fi
}

do_down() {
    log "Tearing down interfaces..."
    if [[ "$TARGET" == "router" ]]; then
        ssh -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" \
            "for f in ${ROUTER_WG_DIR}/*.conf; do wg-quick down \"\$f\" 2>/dev/null || true; done"
    else
        for f in "${NAS_WG_CONF}"/*.conf; do
            sudo wg-quick down "$f" 2>/dev/null || true
        done
    fi
}

do_status() {
    log "--- WireGuard Status Matrix ---"

    local wg_bin="wg"
    local remote_cmd
    if [[ "$TARGET" == "router" ]]; then
        remote_cmd="ssh -p $ROUTER_SSH_PORT $ROUTER_HOST"
    else
        remote_cmd="sudo"
    fi

    # 1. Check if the interface is actually active in the kernel
    if ! $remote_cmd "$wg_bin" show > /dev/null 2>&1; then
        echo "❌ Status: WireGuard service is DOWN on $TARGET"
        return
    fi

    # 2. Print Header
    printf "%-18s %-10s %-18s %-12s %-10s\n" "PEER NAME" "IFACE" "VPN IPv4" "STATUS" "ACCESS"
    echo "--------------------------------------------------------------------------------"

    # 3. Parse enriched peer-map.tsv
    # pubkey name iface ipv4 ipv6 access lan
    while IFS=$'\t' read -r pubkey name iface ipv4 ipv6 access lan; do
        [[ "$pubkey" == "pubkey" ]] && continue # Skip header

        # Get latest handshake timestamp
        local handshake
        handshake=$($remote_cmd "$wg_bin" show "$iface" latest-handshakes 2>/dev/null | grep "$pubkey" | awk '{print $2}' || echo "0")

        local status
        if [[ "$handshake" -eq 0 ]]; then
            status="Offline"
        else
            # Calculate human-readable 'Last Seen' or simply 'Active'
            local now=$(date +%s)
            local diff=$((now - handshake))
            if [[ "$diff" -lt 120 ]]; then
                status="Active"
            else
                status="Idle"
            fi
        fi

        printf "%-18s %-10s %-18s %-12s %-10s\n" "$name" "$iface" "$ipv4" "$status" "$access"
    done < "$PEER_MAP"
}

# --- Guard & Execute ---
[[ -z "$TARGET" ]] && { echo "Usage: $0 {nas|router} {install|up|down|status}"; exit 1; }

case "$MODE" in
    install) do_install ;;
    up)      do_up ;;
    down)    do_down ;;
    status)  do_status ;;
    *)       echo "Unknown mode: $MODE for target: $TARGET"; exit 1 ;;
esac