#!/usr/bin/env bash
set -euo pipefail

: "${WG_ROOT:?WG_ROOT must be exported}"
: "${WG_SUBNETS_MK:?WG_SUBNETS_MK must be provided by Make}"

INPUT_DIR="${WG_ROOT}/input"
IFACES_TSV="${INPUT_DIR}/wg-interfaces.tsv"

# --- temp file with guaranteed cleanup ---
tmp="$(mktemp -p /run homelab.ifc.tmp.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

declare -A IF_HOST IF_ADDR_V4 IF_ADDR_V6

# --- load interface metadata (ignore unused columns) ---
while IFS=$'\t' read -r iface host _ _ v4 v6 _; do
    [[ -z "$iface" || "$iface" == "iface" || "$iface" == "#"* ]] && continue
    IF_HOST["$iface"]="$host"
    IF_ADDR_V4["$iface"]="$v4"
    IF_ADDR_V6["$iface"]="$v6"
done < "$IFACES_TSV"

# --- find router interface ---
router_iface=""
for iface in "${!IF_HOST[@]}"; do
    if [[ "${IF_HOST[$iface]}" == "router" ]]; then
        router_iface="$iface"
        break
    fi
done

[[ -z "$router_iface" ]] && {
    echo "ERROR: No router WG interface found" >&2
    exit 1
}

# --- compute IPv4 network ---
ipv4_network() {
    local cidr="$1"
    local ip="${cidr%/*}" mask="${cidr#*/}"

    local o1 o2 o3 o4
    IFS=. read -r o1 o2 o3 o4 <<<"$ip"

    local ip_int=$(( (o1<<24)|(o2<<16)|(o3<<8)|o4 ))
    local mask_int=$(( 0xFFFFFFFF << (32-mask) & 0xFFFFFFFF ))
    local net_int=$(( ip_int & mask_int ))

    printf "%d.%d.%d.%d/%d" \
        $((net_int>>24&255)) \
        $((net_int>>16&255)) \
        $((net_int>>8&255)) \
        $((net_int&255)) \
        "$mask"
}

v4_net="$(ipv4_network "${IF_ADDR_V4[$router_iface]}")"

# --- compute IPv6 subnet ---
raw_v6="${IF_ADDR_V6[$router_iface]}"

if [[ "$raw_v6" == "-" || -z "$raw_v6" ]]; then
    v6_net=""
else
    addr_v6="${raw_v6%/*}"

    # Router IPv6 must end in ::1 (host address ➡️ network prefix)
    if [[ "$addr_v6" == *::1 ]]; then
        prefix_v6="${addr_v6%1}"
    else
        echo "ERROR: Router IPv6 '$addr_v6' does not end in '::1'." >&2
        echo "ERROR: Update wg-interfaces.tsv to use a router host address ending in ::1." >&2
        exit 1
    fi

    v6_net="${prefix_v6}/64"
fi

# --- write output atomically ---
cat > "$tmp" <<EOF
# Generated — DO NOT EDIT
WG_ROUTER_SUBNET_V4 := $v4_net
WG_ROUTER_SUBNET_V6 := $v6_net
EOF

install -m 0644 "$tmp" "$WG_SUBNETS_MK"
