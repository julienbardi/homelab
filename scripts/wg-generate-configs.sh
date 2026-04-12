#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/volume1/homelab/wireguard"
INPUT_DIR="$BASE_DIR/input"
OUTPUT_DIR="$BASE_DIR/output"
KEY_DIR="$BASE_DIR/keys"
IFACES_TSV="$INPUT_DIR/wg-interfaces.tsv"
CLIENTS_TSV="$INPUT_DIR/clients.tsv"
OUT_SERVER="$OUTPUT_DIR/server"
OUT_ROUTER="$OUTPUT_DIR/router"
OUT_CLIENTS="$OUTPUT_DIR/clients"

mkdir -p "$OUT_SERVER" "$OUT_ROUTER" "$OUT_CLIENTS" "$KEY_DIR/servers" "$KEY_DIR/clients"
declare -A IF_HOST IF_PORT IF_ADDR_V4 IF_ADDR_V6 IF_ENABLED
source /usr/local/bin/common.sh

hash_to_host_octet() {
    local key="$1"
    local h=$(printf '%s' "$key" | sha256sum | cut -c1-6)
    local dec=$(( 0x$h ))
    echo $(( (dec % 241) + 10 ))
}

alloc_client_ip_v4() {
    local iface="$1"
    local client_name="$2"
    local base_ip="${IF_ADDR_V4[$iface]%%/*}"
    local host_oct=$(hash_to_host_octet "${iface}:${client_name}")
    echo "${base_ip%.*}.${host_oct}"
}

load_interfaces() {
    while IFS=$'\t' read -r iface host_id port mtu v4 v6 en; do
        [[ -z "$iface" || "$iface" == "iface" ]] && continue
        IF_HOST["$iface"]="$host_id"
        IF_PORT["$iface"]="$port"
        IF_ADDR_V4["$iface"]="$v4"
        IF_ADDR_V6["$iface"]="$v6"
        IF_ENABLED["$iface"]="$en"
    done < "$IFACES_TSV"
}

server_out_path() {
    local iface="$1"
    [[ "${IF_HOST[$iface]:-nas}" == "nas" ]] && echo "$OUT_SERVER/$iface.conf" || echo "$OUT_ROUTER/$iface.conf"
}

write_server_config() {
    local iface="$1"
    local kb="$KEY_DIR/servers/$iface"
    [[ ! -f "$kb.key" ]] && { umask 077; wg genkey | tee "$kb.key" | wg pubkey > "$kb.pub"; }
    local out=$(server_out_path "$iface")

    local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"
    local v6_address="${v6_prefix}::1/64"

    log "Writing server config: $out"
    cat > "$out" <<EOF
[Interface]
Address = ${IF_ADDR_V4[$iface]}, ${v6_address}
ListenPort = ${IF_PORT[$iface]}
PrivateKey = $(<"$kb.key")
EOF
}

write_client_config() {
    local iface="$1"
    local name="$2"
    local os="$3"
    # Note: access and lan variables should be passed or parsed from your TSV.
    # Defaulting here to 'internet' and 'true' for logic safety.
    local access="internet"
    local lan="true"

    local ck="$KEY_DIR/clients/$name"
    [[ ! -f "$ck.key" ]] && { umask 077; wg genkey | tee "$ck.key" | wg pubkey > "$ck.pub"; }

    local out="$OUT_CLIENTS/$name.conf"
    local ipv4=$(alloc_client_ip_v4 "$iface" "$name")

    # --- FIX 2: CANONICAL IPv6 HEX ---
    local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"
    local o3=$(echo "$ipv4" | cut -d. -f3)
    local o4=$(echo "$ipv4" | cut -d. -f4)
    local host_hex=$(printf '%04x' $(( (o3 << 8) + o4 )))
    local ipv6="${v6_prefix}::${host_hex}/128"

    # CIDR logic for AllowedIPs (Android/S22 fix)
    local if_v4_base="${IF_ADDR_V4[$iface]%%/*}"
    local if_v4_mask="${IF_ADDR_V4[$iface]##*/}"
    local v4_network="${if_v4_base%.*}.0/${if_v4_mask}"
    local v6_network="${IF_ADDR_V6[$iface]}"

    log "Writing client config: $out"

    cat > "$out" <<EOF
[Interface]
PrivateKey = $(<"$ck.key")
Address = ${ipv4}/32, ${ipv6}
DNS = 10.89.12.4, fd89:7a3b:42c0::4
EOF

    [[ "$os" == "windows" ]] && echo "Table = off" >> "$out"

    cat >> "$out" <<EOF

[Peer]
PublicKey = $(<"$KEY_DIR/servers/$iface.pub")
Endpoint = vpn.bardi.ch:${IF_PORT[$iface]}
AllowedIPs = ${v4_network}, ${v6_network}, 10.89.12.0/24, fd89:7a3b:42c0::/64
PersistentKeepalive = 25
EOF

    # Update Server Peer List
    local s_path=$(server_out_path "$iface")
    printf "\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s/32, %s\n" "$name" "$(<"$ck.pub")" "$ipv4" "$ipv6" >> "$s_path"

    # --- FIX 3: ENRICHED PEER MAP ---
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(<"$ck.pub")" "$name" "$iface" "$ipv4" "$ipv6" "$access" "$lan" >> "$OUTPUT_DIR/peer-map.tsv"

    # Generate firewall rules (logic only)
    if [[ "${IF_HOST[$iface]:-nas}" != "nas" ]]; then
        local fw_out="$OUT_ROUTER/${iface}.firewall.sh"
        echo "iptables -I FORWARD 1 -i $iface -s $ipv4 -o br0 -j ACCEPT" >> "$fw_out"
        echo "iptables -I FORWARD 1 -i $iface -s $ipv4 -o eth0 -j ACCEPT" >> "$fw_out"
        echo "iptables -t nat -I POSTROUTING 1 -s $ipv4 -o eth0 -j MASQUERADE" >> "$fw_out"
    fi

    [[ -x $(command -v qrencode) ]] && qrencode -t ansiutf8 < "$out" > "${out%.conf}.qr.txt"
}

main() {
    load_interfaces

    # Clean artifacts
    rm -f "$OUT_SERVER"/*.conf "$OUT_ROUTER"/*.conf "$OUT_CLIENTS"/*.conf "$OUT_CLIENTS"/*.qr.txt "$OUT_ROUTER"/*.firewall.sh || true

    # Initialize enriched peer map
    printf "pubkey\tname\tiface\tipv4\tipv6\taccess\tlan\n" > "$OUTPUT_DIR/peer-map.tsv"

    for i in "${!IF_ENABLED[@]}"; do
        [[ "${IF_ENABLED[$i]}" == "1" ]] && write_server_config "$i"
    done

    grep -vE '^(#|name)' "$CLIENTS_TSV" | while IFS=$'\t' read -r c_name c_dev c_os c_iface others; do
        [[ -n "$c_name" ]] && write_client_config "$c_iface" "$c_name" "$c_os"
    done
}

main "$@"