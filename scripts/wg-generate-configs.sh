#!/usr/bin/env bash
set -euo pipefail

# --- 1. Environment Requirements ---
: "${WG_ROOT:?WG_ROOT must be exported by the Makefile}"
: "${INSTALL_FILE_IF_CHANGED:?INSTALL_FILE_IF_CHANGED must be exported by the Makefile}"

INPUT_DIR="${WG_ROOT}/input"
OUTPUT_DIR="${WG_ROOT}/output"
KEY_DIR="${WG_ROOT}/keys"
IFACES_TSV="$INPUT_DIR/wg-interfaces.tsv"
CLIENTS_TSV="$INPUT_DIR/clients.tsv"
OUT_SERVER="$OUTPUT_DIR/server"
OUT_ROUTER="$OUTPUT_DIR/router"
OUT_CLIENTS="$OUTPUT_DIR/clients"

# Global state
declare -A IF_HOST IF_PORT IF_ADDR_V4 IF_ADDR_V6 IF_ENABLED
source /usr/local/bin/common.sh

# --- 2. Helper Functions ---

install_content() {
    local target="$1"
    local mode="$2"
    local target_base
    target_base=$(basename "$target")
    local tmp_src="/tmp/${target_base}.new"

    cat > "$tmp_src"

    set +e
    run_as_root /usr/local/bin/install_file_if_changed_v2.sh -q \
        "" "22" "$tmp_src" \
        "" "22" "$target" \
        "root" "root" "$mode"
    local rc=$?
    set -e

    rm -f "$tmp_src"
    [[ $rc -eq 0 || $rc -eq 3 ]] && return 0
    return $rc
}

ipv4_network() {
    local cidr="$1"
    local ip="${cidr%/*}"
    local mask="${cidr#*/}"
    local o1 o2 o3 o4
    IFS=. read -r o1 o2 o3 o4 <<EOF
$ip
EOF
    local ip_int=$(( (o1 << 24) | (o2 << 16) | (o3 << 8) | o4 ))
    local mask_int=$(( 0xFFFFFFFF << (32 - mask) & 0xFFFFFFFF ))
    local net_int=$(( ip_int & mask_int ))

    printf "%d.%d.%d.%d/%d" \
        $(( (net_int >> 24) & 0xFF )) \
        $(( (net_int >> 16) & 0xFF )) \
        $(( (net_int >> 8)  & 0xFF )) \
        $((  net_int        & 0xFF )) \
        "$mask"
}

hash_to_host_octet() {
    local key="$1"
    local h=$(printf '%s' "$key" | sha256sum | cut -c1-6)
    local dec=$(( 0x$h ))
    echo $(( (dec % 241) + 10 ))
}

alloc_client_ip_v4() {
    local iface="$1"
    local client_name="$2"
    local v4_raw="${IF_ADDR_V4[$iface]}"
    local base_ip="${v4_raw%/*}"
    local host_oct=$(hash_to_host_octet "${iface}:${client_name}")
    echo "${base_ip%.*}.${host_oct}"
}

load_interfaces() {
    while IFS=$'\t' read -r iface host_id port mtu v4 v6 en; do
        [[ -z "$iface" || "$iface" == "iface" || "$iface" == "#"* ]] && continue
        IF_HOST["$iface"]="$host_id"
        IF_PORT["$iface"]="$port"
        IF_ADDR_V4["$iface"]="$v4"
        IF_ADDR_V6["$iface"]="$v6"
        IF_ENABLED["$iface"]="$en"
    done < "$IFACES_TSV"
}

server_out_path() {
    local iface="$1"
    local host="${IF_HOST[$iface]:-nas}"
    [[ "$host" == "nas" ]] && echo "$OUT_SERVER/$iface.conf" || echo "$OUT_ROUTER/$iface.conf"
}

# --- 3. Core Generation Logic ---

generate_configs() {
    declare -A SERVER_BUFFERS
    local active_ifaces
    active_ifaces=$(for k in "${!IF_ENABLED[@]}"; do echo "$k"; done | sort)

    for iface in $active_ifaces; do
        [[ "${IF_ENABLED[$iface]:-0}" != "1" ]] && continue

        local host="${IF_HOST[$iface]:-nas}"
        local privkey=""
        local pubkey=""
        local kb="$KEY_DIR/servers/$iface"

        if [[ "$host" == "router" ]]; then
            # Attempt to fetch keys from the Asus Router
            echo "--> Fetching keys for $iface from Router (10.89.12.1)..."
            privkey=$($ROUTER_SSH 'nvram get wgs1_priv' 2>/dev/null)
            pubkey=$($ROUTER_SSH 'nvram get wgs1_pub' 2>/dev/null)

            # Validation: If keys are missing, stop and notify operator
            if [[ -z "$privkey" || -z "$pubkey" ]]; then
                echo "ERROR: Could not retrieve WireGuard keys from Asus Merlin ($iface)."
                echo "Please ensure WireGuard is enabled in the Asus Merlin WebUI and configured as 'Server 1'."
                exit 1
            fi

            # Sync to local key directory for consistency with client generation
            echo "$privkey" > "$kb.key"
            echo "$pubkey" > "$kb.pub"
            chmod 600 "$kb.key"
        else
            # Standard NAS logic: Generate keys if they don't exist
            [[ ! -f "$kb.key" ]] && { umask 077; wg genkey | tee "$kb.key" | wg pubkey > "$kb.pub"; }
            privkey=$(<"$kb.key")
        fi

        local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"
        SERVER_BUFFERS[$iface]=$(cat <<EOF
[Interface]
Address = ${IF_ADDR_V4[$iface]}, ${v6_prefix}::1/64
ListenPort = ${IF_PORT[$iface]}
PrivateKey = $privkey
EOF
)
    done

    local peer_map_tmp="/tmp/peer-map.tsv"
    printf "pubkey\tname\tiface\tipv4\tipv6\taccess\tlan\n" > "$peer_map_tmp"

    while IFS=$'\t' read -r c_name c_dev c_os c_iface c_access c_mode c_lan rest; do
        [[ -z "$c_name" || "$c_name" == "#"* ]] && continue
        local ck="$KEY_DIR/clients/$c_name"
        [[ ! -f "$ck.key" ]] && { umask 077; wg genkey | tee "$ck.key" | wg pubkey > "$ck.pub"; }

        local ipv4=$(alloc_client_ip_v4 "$c_iface" "$c_name")
        local c_pubkey=$(cat "$ck.pub")
        local v6_prefix="${IF_ADDR_V6[$c_iface]%%::*}"
        local o3=$(echo "$ipv4" | cut -d. -f3); local o4=$(echo "$ipv4" | cut -d. -f4)
        local host_hex=$(printf '%04x' $(( (o3 << 8) + o4 )))
        local ipv6="${v6_prefix}::${host_hex}"

        install_content "$OUT_CLIENTS/$c_name.conf" "0600" <<EOF
[Interface]
PrivateKey = $(<"$ck.key")
Address = ${ipv4}/32, ${ipv6}/128
DNS = ${NAS_LAN_IP:-10.89.12.4}, ${NAS_LAN_IP6:-fd89:7a3b:42c0::4}
$( [[ "$c_os" == "windows" ]] && echo "Table = off" )

[Peer]
PublicKey = $(<"$KEY_DIR/servers/$c_iface.pub")
Endpoint = vpn.bardi.ch:${IF_PORT[$c_iface]}
AllowedIPs = $( [[ "$c_access" == "full" ]] && echo "0.0.0.0/0, ::/0" || echo "$(ipv4_network "${IF_ADDR_V4[$c_iface]}"), ${IF_ADDR_V6[$c_iface]}, 10.89.12.0/24, fd89:7a3b:42c0::/64" )
PersistentKeepalive = 25
EOF

        SERVER_BUFFERS[$c_iface]+=$(printf "\n\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s/32, %s/128" "$c_name" "$c_pubkey" "$ipv4" "$ipv6")
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$c_pubkey" "$c_name" "$c_iface" "$ipv4" "$ipv6" "$c_access" "$c_lan" >> "$peer_map_tmp"
    done < <(grep -vE '^(#|name)' "$CLIENTS_TSV")

    for iface in "${!SERVER_BUFFERS[@]}"; do
        echo "${SERVER_BUFFERS[$iface]}" | install_content "$(server_out_path "$iface")" "0600"
    done

    install_content "$OUTPUT_DIR/peer-map.tsv" "0644" < "$peer_map_tmp"
    rm -f "$peer_map_tmp"
}

generate_router_firewall() {
    local fw_out="$OUT_ROUTER/wg-firewall.sh"
    local dns_v4="${NAS_LAN_IP:-10.89.12.4}"
    local dns_v6="${NAS_LAN_IP6:-fd89:7a3b:42c0::4}"
    local lan_v4="10.89.12.0/24"
    local lan_v6="fd89:7a3b:42c0::/64"
    local peer_map_local="/tmp/peer-map-fw.tmp"

    run_as_root cat "$OUTPUT_DIR/peer-map.tsv" > "$peer_map_local"

    local buffer
    buffer=$(cat <<EOF
#!/bin/sh
# Generated - DO NOT EDIT
set -e

# Basic State Tracking
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
EOF
)

    local sorted_ifaces
    sorted_ifaces=$(for k in "${!IF_HOST[@]}"; do echo "$k"; done | sort)

    for iface in $sorted_ifaces; do
        local host="${IF_HOST[$iface]:-}"
        [[ -z "$host" ]] && continue

        if [[ "$host" == "router" ]]; then
            local port="${IF_PORT[$iface]}"
            buffer="${buffer}
# --- ${iface} (Port ${port}) ---
iptables -C INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport ${port} -j ACCEPT
ip6tables -C INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null || ip6tables -I INPUT 1 -p udp --dport ${port} -j ACCEPT"

            while IFS=$'\t' read -r pub name ifc v4 v6 acc lan; do
                [[ "$ifc" != "$iface" ]] && continue

                # Rule 1: LAN Access (if lan == 1)
                if [[ "$lan" == "1" ]]; then
                    buffer="${buffer}
iptables -C FORWARD -i ${iface} -s ${v4}/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i ${iface} -s ${v4}/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i ${iface} -s ${v6}/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i ${iface} -s ${v6}/128 -o br0 -j ACCEPT"
                else
                    # Restricted: Only DNS/Router access
                    buffer="${buffer}
iptables -C FORWARD -i ${iface} -s ${v4}/32 -d ${dns_v4}/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i ${iface} -s ${v4}/32 -d ${dns_v4}/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i ${iface} -s ${v6}/128 -d ${dns_v6}/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i ${iface} -s ${v6}/128 -d ${dns_v6}/128 -o br0 -j ACCEPT"
                fi

                # Rule 2: Internet Access (if acc == full)
                if [[ "$acc" == "full" ]]; then
                    buffer="${buffer}
iptables -t nat -C POSTROUTING -s ${v4}/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s ${v4}/32 -j MASQUERADE
iptables -C FORWARD -i ${iface} -s ${v4}/32 ! -d ${lan_v4} -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i ${iface} -s ${v4}/32 ! -d ${lan_v4} -j ACCEPT
ip6tables -C FORWARD -i ${iface} -s ${v6}/128 ! -d ${lan_v6} -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i ${iface} -s ${v6}/128 ! -d ${lan_v6} -j ACCEPT"
                fi
            done < <(grep -vE '^(#|pubkey)' "$peer_map_local")
        fi
    done

    printf "%s\n" "${buffer}" | install_content "$fw_out" "0755"
    rm -f "$peer_map_local"
}

main() {
    load_interfaces
    generate_configs
    generate_router_firewall
}

main "$@"