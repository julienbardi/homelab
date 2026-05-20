#!/usr/bin/env bash
set -euo pipefail

TMPDIR="${TMPDIR:-/run/user/$(id -u)/homelab}"
mkdir -p "$TMPDIR"

# --- 1. Environment Requirements ---
: "${WG_ROOT:?WG_ROOT must be exported by the Makefile}"
: "${INSTALL_FILE_IF_CHANGED:?INSTALL_FILE_IF_CHANGED must be exported by the Makefile}"
: "${LAN_NAS:?LAN_NAS must be exported by the Makefile}"
: "${LAN6_NAS:?LAN6_NAS must be exported by the Makefile}"
: "${LAN_ROUTER:?LAN_ROUTER must be exported by the Makefile}"

INPUT_DIR="${WG_ROOT}/input"
OUTPUT_DIR="${WG_ROOT}/output"
KEY_DIR="${WG_ROOT}/keys"
IFACES_TSV="$INPUT_DIR/wg-interfaces.tsv"
CLIENTS_TSV="$INPUT_DIR/clients.tsv"
OUT_SERVER="$OUTPUT_DIR/server"
OUT_ROUTER="$OUTPUT_DIR/router"
OUT_CLIENTS="$OUTPUT_DIR/clients"

declare -A IF_HOST IF_PORT IF_ADDR_V4 IF_ADDR_V6 IF_ENABLED
source /usr/local/bin/common.sh

# --- Canonical router SSH (authoritative, non‑drifting) ---
: "${SSH_USER_ROUTER:?SSH_USER_ROUTER required}"
: "${ROUTER_ADDR:?ROUTER_ADDR required}"
: "${ROUTER_SSH_PORT:=2222}"
: "${SSH_OPTS:=-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes}"
: "${ROUTER_IDENTITY:=$HOME/.ssh/id_ed25519}"

ROUTER_SSH_CMD=(ssh ${SSH_OPTS} -i "${ROUTER_IDENTITY}" -p "${ROUTER_SSH_PORT}" "${SSH_USER_ROUTER}@${ROUTER_ADDR}")

# --- 2. Helpers -------------------------------------------------------------

install_content() {
    local target="$1" mode="$2"
    local tmp_src=
    tmp_src=$(mktemp -p "$TMPDIR" homelab.content.XXXXXX)

    cat > "$tmp_src"

    set +e
    local op_group rc
    op_group="$(id -gn)"
    run_as_root /usr/local/bin/install_file_if_changed_v2.sh -q \
        "" "22" "$tmp_src" \
        "" "22" "$target" \
        "root" "$op_group" "$mode"
    rc=$?
    set -e

    rm -f "$tmp_src"
    [[ $rc -eq 0 || $rc -eq 3 ]]
}

ipv4_network() {
    local cidr="$1"
    local ip="${cidr%/*}" mask="${cidr#*/}"
    local o1 o2 o3 o4
    IFS=. read -r o1 o2 o3 o4 <<<"$ip"
    local ip_int=$(( (o1<<24)|(o2<<16)|(o3<<8)|o4 ))
    local mask_int=$(( 0xFFFFFFFF << (32-mask) & 0xFFFFFFFF ))
    local net_int=$(( ip_int & mask_int ))
    printf "%d.%d.%d.%d/%d" \
        $((net_int>>24&255)) $((net_int>>16&255)) \
        $((net_int>>8&255))  $((net_int&255)) "$mask"
}

hash_to_host_octet() {
    local h; h=$(printf '%s' "$1" | sha256sum | cut -c1-6)
    echo $(( (0x$h % 241) + 10 ))
}

alloc_client_ip_v4() {
    local iface="$1" name="$2"
    local v4_raw="${IF_ADDR_V4[$iface]}"
    local base="${v4_raw%/*}"
    local host_oct; host_oct=$(hash_to_host_octet "${iface}:${name}")
    echo "${base%.*}.${host_oct}"
}

fw_lan() {
    local iface="$1" v4="$2" v6="$3"
    cat <<EOF
iptables -C FORWARD -i $iface -s $v4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i $iface -s $v4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i $iface -s $v6/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i $iface -s $v6/128 -o br0 -j ACCEPT
EOF
}

fw_dns_only() {
    local iface="$1" v4="$2" v6="$3" dns4="$4" dns6="$5"
    cat <<EOF
iptables -C FORWARD -i $iface -s $v4/32 -d $dns4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i $iface -s $v4/32 -d $dns4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i $iface -s $v6/128 -d $dns6/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i $iface -s $v6/128 -d $dns6/128 -o br0 -j ACCEPT
EOF
}

fw_inet() {
    local iface="$1" v4="$2" v6="$3" lan4="$4" lan6="$5"
    # NOTE: This function only runs for router-terminated interfaces (wgs1).
    # NAS-terminated interfaces (wg7, etc.) are skipped by generate_router_firewall()
    # and their IPv6 internet is handled entirely by NAS nftables NAT66 (homelab_nat6)
    cat <<EOF
iptables -t nat -C POSTROUTING -s $v4/32 -o $wan_if -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s $v4/32 -o $wan_if -j MASQUERADE
iptables -C FORWARD -i $iface -s $v4/32 -o $wan_if ! -d $lan4 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i $iface -s $v4/32 -o $wan_if ! -d $lan4 -j ACCEPT
# IPv6 internet: NAT66 not available on this router (Asus Merlin lacks CONFIG_IP6_NF_NAT).
# REJECT (not DROP) so the client gets an immediate ICMPv6 no-route error and Happy Eyeballs
# retries on IPv4 within ~100ms. Traffic is still routed into the tunnel (no location leak).
# ::/0 remains in wgs1 client AllowedIPs for full tunnel / location privacy.
ip6tables -C FORWARD -i $iface -s $v6/128 ! -d $lan6 -j REJECT --reject-with icmp6-no-route 2>/dev/null || ip6tables -I FORWARD 2 -i $iface -s $v6/128 ! -d $lan6 -j REJECT --reject-with icmp6-no-route
EOF
}

load_interfaces() {
    while IFS=$'\t' read -r iface host port mtu v4 v6 en; do
        [[ -z "$iface" || "$iface" == "iface" || "$iface" == "#"* ]] && continue
        IF_HOST["$iface"]="$host"
        IF_PORT["$iface"]="$port"
        IF_ADDR_V4["$iface"]="$v4"
        IF_ADDR_V6["$iface"]="$v6"
        IF_ENABLED["$iface"]="$en"
    done < "$IFACES_TSV"
}

server_out_path() {
    [[ "${IF_HOST[$1]}" == "router" ]] && echo "$OUT_ROUTER/$1.conf" || echo "$OUT_SERVER/$1.conf"
}

# --- 3. Config Generation ---------------------------------------------------

generate_configs() {
    declare -A SERVER_BUFFERS
    local peer_map_tmp
    peer_map_tmp=$(mktemp -p "$TMPDIR" homelab.ifc.tmp.XXXXXX)
    printf "pubkey\tname\tiface\tipv4\tipv6\taccess\tlan\n" > "$peer_map_tmp"

    for iface in $(printf '%s\n' "${!IF_ENABLED[@]}" | sort); do
        [[ "${IF_ENABLED[$iface]}" != "1" ]] && continue

        local kb="$KEY_DIR/servers/$iface"
        local host="${IF_HOST[$iface]}"
        local priv pub

        if [[ "$host" == "router" ]]; then
            # Router keys come from nvram
            priv=$("${ROUTER_SSH_CMD[@]}" nvram get wgs1_priv 2>/dev/null || true)
            pub=$("${ROUTER_SSH_CMD[@]}" nvram get wgs1_pub 2>/dev/null || true)
            [[ -z "$priv" || -z "$pub" ]] && { echo "ERROR: Missing router keys for $iface"; exit 1; }
            (umask 077; echo "$priv" > "$kb.key")
            echo "$pub"  > "$kb.pub"
        else
            # NAS/server keys generated locally
            [[ ! -f "$kb.key" ]] && { umask 077; wg genkey | tee "$kb.key" | wg pubkey > "$kb.pub"; }
            priv=$(<"$kb.key")
        fi

        local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"

        #
        # *** CRITICAL FIX ***
        # Router gets RAW wg config (NO Address=)
        # NAS/server keeps wg-quick config (WITH Address=)
        #
        if [[ "$host" == "router" ]]; then
            SERVER_BUFFERS[$iface]=$(cat <<EOF
[Interface]
PrivateKey = $priv
ListenPort = ${IF_PORT[$iface]}
EOF
)
        else
            SERVER_BUFFERS[$iface]=$(cat <<EOF
[Interface]
Address = ${IF_ADDR_V4[$iface]}, ${v6_prefix}::1/64
ListenPort = ${IF_PORT[$iface]}
PrivateKey = $priv
EOF
)
        fi
    done

    #
    # --- CLIENT GENERATION (unchanged) ---
    #
    while IFS=$'\t' read -r name dev os iface mode acc lan rest; do
        [[ -z "$name" || "$name" == "#"* || "$name" == "name" ]] && continue

        local ck="$KEY_DIR/clients/$name"
        [[ ! -f "$ck.key" ]] && { umask 077; wg genkey | tee "$ck.key" | wg pubkey > "$ck.pub"; }

        local ipv4; ipv4=$(alloc_client_ip_v4 "$iface" "$name")
        local o3 o4 host_hex
        o3=$(echo "$ipv4" | cut -d. -f3)
        o4=$(echo "$ipv4" | cut -d. -f4)
        host_hex=$(printf '%04x' $(( (o3<<8) + o4 )))

        local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"
        local ipv6="${v6_prefix}::${host_hex}"

        local host_id="${IF_HOST[$iface]}"
        # Endpoint MUST always be the bare domain (WAN IP, no split-horizon override).
		# Using host_id.domain (e.g. router.bardi.ch) is wrong for LAN clients because
		# Unbound's split-horizon returns the router's *internal* IP, causing the
		# Wireguard handshake to target teh wrong host and silently black-hole.
		local endpoint_host="${DNS_TOPDOMAIN_NAME}"

        install_content "$OUT_CLIENTS/$name.conf" "0600" <<EOF
[Interface]
PrivateKey = $(<"$ck.key")
Address = ${ipv4}/32, ${ipv6}/128
DNS = ${LAN_NAS}, ${LAN6_NAS}, ${LAN_ROUTER}
$( [[ "$os" == "windows" ]] && echo "Table = auto" )

[Peer]
PublicKey = $(<"$KEY_DIR/servers/$iface.pub")
Endpoint = ${endpoint_host}:${IF_PORT[$iface]}
AllowedIPs = $(
    if [[ "$os" == "windows" ]]; then
        if [[ "$acc" == "full" ]]; then
            # Windows full-tunnel + LAN bypass.
            # ::/0 is intentionally included: routing ALL IPv6 through the tunnel prevents
            # the client's native IPv6 from bypassing the VPN and leaking their real location.
            # At the tunnel exit the router REJECTs (not drops) non-LAN IPv6, so the OS
            # fails fast via Happy Eyeballs and retries on IPv4 (~100ms). No black hole.
            # IPv6 internet will work once NAT66 is operational (see wg7 notes)
            echo "10.89.12.0/24, fd89:7a3b:42c0::/64, 0.0.0.0/0, ::/0"
        else
            # Windows restricted mode
            echo "$(ipv4_network "${IF_ADDR_V4[$iface]}"), ${IF_ADDR_V6[$iface]}"
        fi
    else
        # Linux / Android / iOS / macOS
        if [[ "$acc" == "full" ]]; then
            # ::/0 intentionally included - see Windows comment above.
            echo "0.0.0.0/0, ::/0"
        else
            echo "$(ipv4_network "${IF_ADDR_V4[$iface]}"), ${IF_ADDR_V6[$iface]}, 10.89.12.0/24, fd89:7a3b:42c0::/64"
        fi
    fi
)
PersistentKeepalive = 25
EOF

        SERVER_BUFFERS[$iface]+=$'\n\n'"[Peer]
# $name
PublicKey = $(<"$ck.pub")
AllowedIPs = ${ipv4}/32, ${ipv6}/128"

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$(<"$ck.pub")" "$name" "$iface" "$ipv4" "$ipv6" "$acc" "$lan" >> "$peer_map_tmp"
    done < "$CLIENTS_TSV"

    #
    # --- WRITE SERVER CONFIGS ---
    #
    for iface in "${!SERVER_BUFFERS[@]}"; do
        echo "${SERVER_BUFFERS[$iface]}" | install_content "$(server_out_path "$iface")" "0640"
    done

    install_content "$OUTPUT_DIR/peer-map.tsv" "0644" < "$peer_map_tmp"
    rm -f "$peer_map_tmp"
}

# --- 4. Firewall Generation -------------------------------------------------

generate_router_firewall() {
    local fw_out="$OUT_ROUTER/wg-firewall.sh"
    local dns_v4="${NAS_LAN_IP:-10.89.12.4}"
    local dns_v6="${NAS_LAN_IP6:-fd89:7a3b:42c0::4}"
    local lan_v4="10.89.12.0/24"
    local lan_v6="fd89:7a3b:42c0::/64"
    local wan_if="eth0"   # set to your actual WAN interface

    local peer_map_local="" tmp=""
    peer_map_local=$(mktemp -p "$TMPDIR" homelab.ifc.tmp.XXXXXX)
    tmp=$(mktemp -p "$TMPDIR" homelab.ifc.tmp.XXXXXX)
    trap 'rm -f "${peer_map_local:-}" "${tmp:-}"' EXIT

    cat "$OUTPUT_DIR/peer-map.tsv" > "$peer_map_local"

    local buffer
    buffer=$(cat <<'EOF'
#!/bin/sh
# Generated - DO NOT EDIT
set -e

ip link show wgs1 >/dev/null 2>&1 || exit 0

# Ensure conntrack rule exists
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
ip6tables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- Cleanup old WG rules ---
iptables -S FORWARD | grep -E 'wgs1|10\.89\.101' | sed 's/^-A/iptables -D/' | sh
iptables -t nat -S POSTROUTING | grep -E '10\.89\.101' | sed 's/^-A/iptables -t nat -D/' | sh

# --- Dynamic WG zone rule placement ---
# Find conntrack rule index on router (BusyBox-safe)
CT_LINE="$(iptables -S FORWARD 2>/dev/null | awk '/ctstate ESTABLISHED,RELATED/ {print NR; exit}')"
if [ -z "$CT_LINE" ]; then CT_LINE=1; fi

# Insert WG rules immediately after conntrack
iptables -C FORWARD -i wgs1 -j ACCEPT 2>/dev/null || iptables -I FORWARD $((CT_LINE+1)) -i wgs1 -j ACCEPT
iptables -C FORWARD -o wgs1 -j ACCEPT 2>/dev/null || iptables -I FORWARD $((CT_LINE+2)) -o wgs1 -j ACCEPT
iptables -C FORWARD -i wgs1 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD $((CT_LINE+3)) -i wgs1 -o br0 -j ACCEPT
iptables -C FORWARD -i br0 -o wgs1 -j ACCEPT 2>/dev/null || iptables -I FORWARD $((CT_LINE+4)) -i br0 -o wgs1 -j ACCEPT
EOF
)

    for iface in $(printf '%s\n' "${!IF_HOST[@]}" | sort); do
        [[ "${IF_HOST[$iface]}" != "router" ]] && continue
        local port="${IF_PORT[$iface]}"

        buffer+=$'\n'"# --- ${iface} (Port ${port}) ---"
        buffer+=$'\n'"iptables -C INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport ${port} -j ACCEPT"
        buffer+=$'\n'"ip6tables -C INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null || ip6tables -I INPUT 1 -p udp --dport ${port} -j ACCEPT"

        while IFS=$'\t' read -r pub name ifc v4 v6 acc lan; do
            [[ "$ifc" != "$iface" ]] && continue

            if [[ "$lan" == "1" ]]; then
                buffer+=$'\n'"$(fw_lan "$iface" "$v4" "$v6")"
            else
                buffer+=$'\n'"$(fw_dns_only "$iface" "$v4" "$v6" "$dns_v4" "$dns_v6")"
            fi

            if [[ "$acc" == "full" ]]; then
                buffer+=$'\n'"$(fw_inet "$iface" "$v4" "$v6" "$lan_v4" "$lan_v6")"
                # NAT66 for IPv6 WAN
                #buffer+=$'\n'"ip6tables -t nat -C POSTROUTING -s fd89:7a3b:42c0:101::/64 -o eth0 -j MASQUERADE 2>/dev/null || ip6tables -t nat -A POSTROUTING -s fd89:7a3b:42c0:101::/64 -o eth0 -j MASQUERADE"
                # NAT66 intentionally NOT generated:
                # Asus Merlin (RT-AX86U) kernel lacks CONFIG_IP6_NF_NAT.
                # The ip6tables nar table does not exist on this router.
                #
                # IPv6 internet for wgs1 clients is rejected at the router (ICMPv6 no-route);
                # OD Happy Eyeballs falls back to IPv4 in ~100ms. No black hole, no location leak.
                # wg7 IPv6 internet is unaffected - it is NAS-terminated and uses NAS NAT66.
            fi
        done < <(grep -vE '^(#|pubkey)' "$peer_map_local")

    done

    printf "%s\n" "$buffer" > "$tmp"

    if [[ ! -f "$fw_out" ]] || ! cmp -s "$tmp" "$fw_out"; then
        install_content "$fw_out" "0755" < "$tmp"
    fi
}

# --- 6. Main ---------------------------------------------------------------

main() {
    load_interfaces
    generate_configs
    generate_router_firewall
}

main "$@"
