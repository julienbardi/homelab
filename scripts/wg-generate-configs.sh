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

# Helper: Only write if content hash differs from disk
write_if_changed() {
    local target="$1"
    local content
    content=$(cat)

    if [[ -f "$target" ]]; then
        local old_hash new_hash
        old_hash=$(md5sum "$target" | awk '{print $1}')
        new_hash=$(echo "$content" | md5sum | awk '{print $1}')
        if [[ "$old_hash" == "$new_hash" ]]; then
            return 0
        fi
    fi
    echo "$content" > "$target"
    log "Updated: $target"
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

generate_configs() {
    declare -A SERVER_BUFFERS

    # 1. Initialize server buffers in current shell
    for iface in "${!IF_ENABLED[@]}"; do
        [[ "${IF_ENABLED[$iface]}" != "1" ]] && continue

        local kb="$KEY_DIR/servers/$iface"
        [[ ! -f "$kb.key" ]] && { umask 077; wg genkey | tee "$kb.key" | wg pubkey > "$kb.pub"; }

        local v6_prefix="${IF_ADDR_V6[$iface]%%::*}"
        local v6_address="${v6_prefix}::1/64"

        SERVER_BUFFERS[$iface]=$(cat <<EOF
[Interface]
Address = ${IF_ADDR_V4[$iface]}, ${v6_address}
ListenPort = ${IF_PORT[$iface]}
PrivateKey = $(<"$kb.key")
EOF
)
    done

    # 2. Process Clients using Process Substitution to avoid subshell array loss
    printf "pubkey\tname\tiface\tipv4\tipv6\taccess\tlan\n" > "$OUTPUT_DIR/peer-map.tsv.tmp"

    while IFS=$'\t' read -r c_name c_dev c_os c_iface c_access c_mode c_lan rest; do
        [[ -z "$c_name" ]] && continue

        local ck="$KEY_DIR/clients/$c_name"
        [[ ! -f "$ck.key" ]] && { umask 077; wg genkey | tee "$ck.key" | wg pubkey > "$ck.pub"; }

        local out="$OUT_CLIENTS/$c_name.conf"
        local ipv4=$(alloc_client_ip_v4 "$c_iface" "$c_name")
        local v6_prefix="${IF_ADDR_V6[$c_iface]%%::*}"
        local o3=$(echo "$ipv4" | cut -d. -f3)
        local o4=$(echo "$ipv4" | cut -d. -f4)
        local host_hex=$(printf '%04x' $(( (o3 << 8) + o4 )))
        local ipv6="${v6_prefix}::${host_hex}/128"

        local if_v4_base="${IF_ADDR_V4[$c_iface]%%/*}"
        local if_v4_mask="${IF_ADDR_V4[$c_iface]##*/}"
        local v4_network="${if_v4_base%.*}.0/${if_v4_mask}"
        local v6_network="${IF_ADDR_V6[$c_iface]}"

        # Write Client File
        cat <<EOF | write_if_changed "$out"
[Interface]
PrivateKey = $(<"$ck.key")
Address = ${ipv4}/32, ${ipv6}
DNS = 10.89.12.4, fd89:7a3b:42c0::4
$( [[ "$c_os" == "windows" ]] && echo "Table = off" )

[Peer]
PublicKey = $(<"$KEY_DIR/servers/$c_iface.pub")
Endpoint = vpn.bardi.ch:${IF_PORT[$c_iface]}
AllowedIPs = ${v4_network}, ${v6_network}, 10.89.12.0/24, fd89:7a3b:42c0::/64
PersistentKeepalive = 25
EOF

        # Add to Peer Map
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$(<"$ck.pub")" "$c_name" "$c_iface" "$ipv4" "$ipv6" "$c_access" "$c_lan" >> "$OUTPUT_DIR/peer-map.tsv.tmp"

        # Append Peer to Server Buffer (Now persists!)
        SERVER_BUFFERS[$c_iface]+=$(printf "\n\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s/32, %s" "$c_name" "$(<"$ck.pub")" "$ipv4" "$ipv6")

        # QR Check
        if [[ -x $(command -v qrencode) ]]; then
            local qr_out="${out%.conf}.qr.txt"
            [[ ! -f "$qr_out" || "$out" -nt "$qr_out" ]] && qrencode -t ansiutf8 < "$out" > "$qr_out"
        fi
    done < <(grep -vE '^(#|name)' "$CLIENTS_TSV")

    # 3. Flush Server Buffers
    for iface in "${!SERVER_BUFFERS[@]}"; do
        local s_out=$(server_out_path "$iface")
        echo "${SERVER_BUFFERS[$iface]}" | write_if_changed "$s_out"
    done
}

main() {
    load_interfaces
    generate_configs
    mv "$OUTPUT_DIR/peer-map.tsv.tmp" "$OUTPUT_DIR/peer-map.tsv"
}

main "$@"