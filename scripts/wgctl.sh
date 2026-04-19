#!/usr/bin/env bash
set -euo pipefail

# --- Authoritative Context ---
: "${ROUTER_HOST:?Missing ROUTER_HOST}"
: "${ROUTER_SSH_PORT:?Missing ROUTER_SSH_PORT}"
: "${ROUTER_WG_DIR:?Missing ROUTER_WG_DIR}"
: "${WG_ROOT:?Missing WG_ROOT}"

# Local paths for NAS/Server execution
NAS_WG_CONF="/etc/wireguard"
INSTALL_FILE_IF_CHANGED="/usr/local/bin/install_file_if_changed_v2.sh"
PEER_MAP="${WG_ROOT}/output/peer-map.tsv"

# Swapped to match Makefile: wgctl.sh [TARGET] [MODE]
TARGET="${1:-}"
MODE="${2:-status}"

# Improved Log function with fixed-width device tags and icons
log() {
    local icon="⚙️"
    case "$MODE" in
        install) icon="📦" ;;
        up)      icon="🚀" ;;
        down)    icon="🛑" ;;
        status)  icon="📊" ;;
    esac

    # Aligns [nas   ] and [router] perfectly
    local tag
    [[ "$TARGET" == "nas" ]] && tag="nas   " || tag="router"

    echo "$icon [$tag] $1"
}

# --- Actions ---

do_install() {
    #log "Initiating atomic IFC installation..."

    if [[ "$TARGET" == "router" ]]; then
        # Deployment from NAS output -> Router JFFS
        for conf in "${WG_ROOT}/output/router"/*.conf; do
            [[ -e "$conf" ]] || continue
            "$INSTALL_FILE_IF_CHANGED" -q "" "22" "$conf" \
                       "$ROUTER_HOST" "$ROUTER_SSH_PORT" "${ROUTER_WG_DIR}/$(basename "$conf")" \
                       "0" "0" "0600"
        done
    elif [[ "$TARGET" == "nas" ]]; then
        # Deployment from NAS output -> NAS /etc/wireguard
        for conf in "${WG_ROOT}/output/server"/*.conf; do
            [[ -e "$conf" ]] || continue
            "$INSTALL_FILE_IF_CHANGED" -q "" "22" "$conf" \
                       "" "22" "${NAS_WG_CONF}/$(basename "$conf")" \
                       "0" "0" "0600"
        done
    fi
}

do_up() {
    log "Bringing up interfaces..."
    if [[ "$TARGET" == "router" ]]; then
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
    local wg_bin="wg"
    local remote_cmd
    local now=$(date +%s)

    if [[ "$TARGET" == "router" ]]; then
        remote_cmd="ssh -p $ROUTER_SSH_PORT $ROUTER_HOST"
        local header_name="• PEER NAME [router]"
    else
        remote_cmd="sudo"
        local header_name="• PEER NAME [nas]"
    fi

    [[ ! -f "$PEER_MAP" ]] && PEER_MAP="/volume1/homelab/wireguard/output/peer-map.tsv"

    # --- PLATINUM OPTIMIZATION: ONE-SHOT DATA GATHERING ---
    # Get all handshakes and all interfaces in just two remote calls
    local all_handshakes
    all_handshakes=$($remote_cmd "$wg_bin" show all latest-handshakes 2>/dev/null || echo "")
    local active_ifaces
    active_ifaces=$($remote_cmd "$wg_bin" show interfaces 2>/dev/null || echo "")
    # ------------------------------------------------------

    local fmt_h="%-22s  %-5s %-15s %-26s %-14s %-3s\n"
    local fmt_d="%-23s %-5s %-15s %-26s %-14s %-3s\n"

    printf "$fmt_h" "$header_name" "IF" "VPN IPv4" "VPN IPv6" "ACCESS" "LAN"
    echo "----------------------------------------------------------------------------------------------------------------"

    while IFS=$'\t' read -r pk nm iface v4 v6 acc lan || [[ -n "$pk" ]]; do
        [[ "$pk" == "pubkey" || "$pk" == "#"* || -z "$pk" ]] && continue
        [[ " $active_ifaces " =~ " $iface " ]] || continue

        # Extract handshake from the one-shot variable instead of forking SSH
        local handshake
        handshake=$(echo "$all_handshakes" | grep "$pk" | awk '{print $3}' || echo "0")
        [[ -z "$handshake" ]] && handshake=0

        local icon="○"
        if [[ "$handshake" -gt 0 ]]; then
            [[ $((now - handshake)) -lt 150 ]] && icon="●" || icon="◌"
        fi

        local disp_v4="${v4%/*}"
        local disp_v6="${v6%/*}"

        printf "$fmt_d" "$icon $nm" "$iface" "$disp_v4" "$disp_v6" "$acc" "$lan"
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