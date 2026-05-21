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
        ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" "
            # Apply WireGuard config
            wg setconf wgs1 ${ROUTER_WG_DIR}/wgs1.conf

            # Assign IPv4 server address
            ip addr add 10.89.101.1/24 dev wgs1 2>/dev/null || true
            # Attempt IPv6 server address - Asus Merlin may not support this.
            # Failure is non-fatal: IPv6 peer rules in wg-firewall.sh will be present
            # but inactive. IPv6 internet for wgs1 clients is rejected at the NAS
            # (bftables REJECT with icmpv6 no-route -> OD falls back to IPv4 instantly).
            # ::/0 remains in client AllowedIPs for location privacy (full tunnel).
            if ip addr add fd89:7a3b:42c0:101::1/64 dev wgs1 2>/dev/null; then
                echo 'wgs1: IPv6 address assigned (fd89:7a3b:42c0:101::1/64)'
            else
                echo 'WARNING: wgs1 IPv6 address could not be assigned. IPv6 WG is not operational on this router.'
                echo 'This is expected on Asus Merlin if IPv6 kernel support is incomplete.'
            fi
        "
    else
        for f in "${NAS_WG_CONF}"/*.conf; do
            sudo wg-quick up "$f" 2>/dev/null || true
        done
    fi
}

do_down() {
    log "Tearing down interfaces..."
    if [[ "$TARGET" == "router" ]]; then
        ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" \
            "for f in ${ROUTER_WG_DIR}/*.conf; do wg-quick down \"\$f\" 2>/dev/null || true; done"
    else
        for f in "${NAS_WG_CONF}"/*.conf; do
            sudo wg-quick down "$f" 2>/dev/null || true
        done
    fi
}

do_status() {
    local wg_bin="wg"
    local -a remote_cmd  # array so each token is a separate word
    local now=$(date +%s)

    if [[ "$TARGET" == "router" ]]; then
        remote_cmd=(ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST")
        local header_name="• PEER NAME [router]"
    else
        remote_cmd=(sudo)
        local header_name="• PEER NAME [nas]"
    fi

    [[ ! -f "$PEER_MAP" ]] && PEER_MAP="/volume1/homelab/wireguard/output/peer-map.tsv"

    # --- PLATINUM OPTIMIZATION: ONE-SHOT DATA GATHERING ---
    # Get all handshakes and all interfaces in just two remote calls
    local all_handshakes
    all_handshakes=$("${remote_cmd[@]}" "$wg_bin" show all latest-handshakes 2>/dev/null || echo "")
    local active_ifaces
    active_ifaces=$("${remote_cmd[@]}" "$wg_bin" show interfaces 2>/dev/null || echo "")
    # ------------------------------------------------------

    # --- Determine dynamic width for the PEER NAME column ---
    max_peer_len=$(awk -F'\t' 'NR>1 {print length($2)}' "$PEER_MAP" | sort -n | tail -1)
    ((max_peer_len < 12)) && max_peer_len=12

    # Header
    printf "• %-*s  %-5s %-15s %-26s %-14s %-3s\n" \
        "$max_peer_len" "PEER NAME" "IF" "VPN IPv4" "VPN IPv6" "ACCESS" "LAN"

    printf "%0.s-" $(seq 1 $((max_peer_len + 80)))
    echo

    # Rows
    while IFS=$'\t' read -r pk nm iface v4 v6 acc lan || [[ -n "$pk" ]]; do
        [[ "$pk" == "pubkey" || "$pk" == "#"* || -z "$pk" ]] && continue
        [[ " $active_ifaces " =~ " $iface " ]] || continue

        local handshake
        # -F treats $pk as a fixed string, not a regex (pubkeys contain +/=)
        handshake=$(echo "$all_handshakes" | grep -F "$pk" | awk '{print $3}' || echo "0")
        [[ -z "$handshake" ]] && handshake=0

        local icon="○"
        if [[ "$handshake" -gt 0 ]]; then
            [[ $((now - handshake)) -lt 150 ]] && icon="●" || icon="◌"
        fi

        local disp_v4="${v4%/*}"
        local disp_v6="${v6%/*}"

        # use $icon computed above, not hardcoded ○
        printf "%s %-*s  %-5s %-15s %-26s %-14s %-3s\n" "$icon" \
            "$max_peer_len" "$nm" "$iface" "$disp_v4" "$disp_v6" "$acc" "$lan"
    done < "$PEER_MAP"

}

# --- Guard & Execute ---
[[ -z "$TARGET" ]] && { echo "Usage: $0 {nas|router} {install|up|down|status}"; exit 1; }

case "$MODE" in
    install) do_install ;;
    up)      do_up ;;
    down)    do_down ;;
    status)  do_status ;;
	install-up)  do_install; do_up ;;
    *)       echo "Unknown mode: $MODE for target: $TARGET"; exit 1 ;;
esac