#!/usr/bin/env bash
# scripts/wg-generate-configs.sh
set -euo pipefail

BASE_DIR="/volume1/homelab/wireguard"
INPUT_DIR="$BASE_DIR/input"
OUTPUT_DIR="$BASE_DIR/output"
KEY_DIR="$BASE_DIR/keys"

HOSTS_TSV="$INPUT_DIR/hosts.tsv"
IFACES_TSV="$INPUT_DIR/wg-interfaces.tsv"
CLIENTS_TSV="$INPUT_DIR/clients.tsv"

OUT_SERVER="$OUTPUT_DIR/server"
OUT_ROUTER="$OUTPUT_DIR/router"
OUT_CLIENTS="$OUTPUT_DIR/clients"

mkdir -p "$OUT_SERVER" "$OUT_ROUTER" "$OUT_CLIENTS" "$KEY_DIR/servers" "$KEY_DIR/clients"

declare -A IF_HOST IF_PORT IF_MTU IF_ADDR_V4 IF_ADDR_V6 IF_ENABLED
declare -A IF_CLIENTS_V4 IF_CLIENTS_V6 IF_CLIENTS_LAN

SCRIPT_NAME="wg-generate-configs"
# shellcheck disable=SC1091
source /usr/local/bin/common.sh

#
# 🔐 SHA‑256–based host octet allocator
#
hash_to_host_octet() {
  local key="$1"
  local h dec
  h=$(printf '%s' "$key" | sha256sum | cut -c1-6)
  dec=$(( 0x$h ))
  echo $(( (dec % 241) + 10 ))
}

alloc_client_ip_v4() {
  local iface="$1" name="$2"
  local addr_v4="${IF_ADDR_V4[$iface]}"
  local base_ip="${addr_v4%%/*}"
  local o1 o2 o3 o4
  IFS='.' read -r o1 o2 o3 o4 <<< "$base_ip"
  local host_oct
  host_oct=$(hash_to_host_octet "${iface}:${name}")
  printf "%s.%s.%s.%s\n" "$o1" "$o2" "$o3" "$host_oct"
}

alloc_client_ip_v6() {
  local iface="$1" name="$2"
  local addr_v6="${IF_ADDR_V6[$iface]}"
  local prefix="${addr_v6%%/*}"
  local host_hex
  host_hex=$(printf '%x' "$(hash_to_host_octet "${iface}:${name}")")
  printf "%s%s\n" "${prefix%::*}::" "${host_hex}"
}

ensure_server_keys() {
  local iface="$1"
  local key_base="$KEY_DIR/servers/$iface"
  if [[ ! -f "$key_base.key" ]]; then
    log "Generating server keypair for ${iface}"
    umask 077
    wg genkey | tee "$key_base.key" | wg pubkey > "$key_base.pub"
  fi
}

ensure_client_keys() {
  local name="$1"
  local key_base="$KEY_DIR/clients/$name"
  if [[ ! -f "$key_base.key" ]]; then
    log "Generating client keypair for ${name}"
    umask 077
    wg genkey | tee "$key_base.key" | wg pubkey > "$key_base.pub"
  fi
}

load_interfaces() {
  while IFS=$'\t' read -r iface host_id listen_port mtu addr_v4 addr_v6 enabled; do
    [[ -z "$iface" || "$iface" == "iface" ]] && continue
    IF_HOST["$iface"]="$host_id"
    IF_PORT["$iface"]="$listen_port"
    IF_MTU["$iface"]="$mtu"
    IF_ADDR_V4["$iface"]="$addr_v4"
    IF_ADDR_V6["$iface"]="$addr_v6"
    IF_ENABLED["$iface"]="$enabled"
  done < "$IFACES_TSV"
}

server_out_path() {
  local iface="$1"
  if [[ "${IF_HOST[$iface]}" == "nas" ]]; then
    printf '%s/%s.conf\n' "$OUT_SERVER" "$iface"
  else
    printf '%s/%s.conf\n' "$OUT_ROUTER" "$iface"
  fi
}

write_server_config() {
  local iface="$1"
  local host_id="${IF_HOST[$iface]}"
  local listen_port="${IF_PORT[$iface]}"
  local mtu="${IF_MTU[$iface]}"
  local addr_v4="${IF_ADDR_V4[$iface]}"
  local addr_v6="${IF_ADDR_V6[$iface]}"

  ensure_server_keys "$iface"
  local key_base="$KEY_DIR/servers/$iface"
  local privkey; privkey=$(<"$key_base.key")

  local out; out=$(server_out_path "$iface")

  log "Writing server config: ${out}"

  cat > "$out" <<EOF
[Interface]
Address = ${addr_v4}, ${addr_v6}
ListenPort = ${listen_port}
PrivateKey = ${privkey}
MTU = ${mtu}

EOF
}

append_peer_to_server() {
  local iface="$1" name="$2" ip_v4="$3" ip_v6="$4" access="$5" lan="$6" v4="$7" v6="$8"
  local key_base="$KEY_DIR/clients/$name"
  local pubkey; pubkey=$(<"$key_base.pub")

  local out; out=$(server_out_path "$iface")

  local allowed_ips=()
  if [[ "$v4" == "1" && -n "$ip_v4" ]]; then
    allowed_ips+=("${ip_v4}/32")
  fi
  if [[ "$v6" == "1" && -n "$ip_v6" ]]; then
    allowed_ips+=("${ip_v6}/128")
  fi
  if [[ "$access" == "full" || "$access" == "internet-only" ]]; then
    allowed_ips+=("0.0.0.0/0" "::/0")
  fi

  log "Appending peer ${name} to ${out}"

  {
    printf '[Peer]\n'
    printf '# %s\n' "$name"
    printf 'PublicKey = %s\n' "$pubkey"
    printf 'AllowedIPs = %s\n' "$(IFS=', '; echo "${allowed_ips[*]}")"
    printf '\n'
  } >> "$out"

  if [[ "$lan" == "0" ]]; then
    {
      printf '# Internet-only client: LAN blocking handled by generated firewall script\n'
      printf '\n'
    } >> "$out"
  fi
}

write_client_config() {
  local iface="$1" name="$2" device="$3" os="$4" access="$5" tunnel_mode="$6" lan="$7" v4="$8" v6="$9" dns_v4="${10}" dns_v6="${11}"

  ensure_client_keys "$name"
  ensure_server_keys "$iface"

  local client_key_base="$KEY_DIR/clients/$name"
  local server_key_base="$KEY_DIR/servers/$iface"

  local privkey; privkey=$(<"$client_key_base.key")
  local server_pub; server_pub=$(<"$server_key_base.pub")

  local ip_v4="" ip_v6=""
  if [[ "$v4" == "1" ]]; then
    ip_v4=$(alloc_client_ip_v4 "$iface" "$name")
  fi
  if [[ "$v6" == "1" ]]; then
    ip_v6=$(alloc_client_ip_v6 "$iface" "$name")
  fi

  local endpoint_port="${IF_PORT[$iface]}"
  local endpoint="bardi.ch:${endpoint_port}"

  local out="$OUT_CLIENTS/$name.conf"
  log "Writing client config: ${out}"

  {
    echo "[Interface]"
    echo "PrivateKey = ${privkey}"

    local addr_line=""
    if [[ "$v4" == "1" && -n "$ip_v4" ]]; then
      addr_line="${ip_v4}/32"
    fi
    if [[ "$v6" == "1" && -n "$ip_v6" ]]; then
      if [[ -n "$addr_line" ]]; then
        addr_line+=", ${ip_v6}/128"
      else
        addr_line="${ip_v6}/128"
      fi
    fi
    echo "Address = ${addr_line}"

    if [[ -n "$ip_v4" ]]; then
        IF_CLIENTS_V4["${iface}"]+="${name}:${ip_v4}:${lan} "
    fi
    if [[ -n "$ip_v6" ]]; then
        IF_CLIENTS_V6["${iface}"]+="${name}:${ip_v6}:${lan} "
    fi

    if [[ -n "$dns_v4" || -n "$dns_v6" ]]; then
      echo -n "DNS = "
      [[ -n "$dns_v4" ]] && echo -n "$dns_v4"
      [[ -n "$dns_v6" ]] && echo -n ", $dns_v6"
      echo
    fi

    echo
    echo "[Peer]"
    echo "PublicKey = ${server_pub}"
    echo "Endpoint = ${endpoint}"
    echo "AllowedIPs = 0.0.0.0/0, ::/0"
    echo "PersistentKeepalive = 25"
  } > "$out"

  append_peer_to_server "$iface" "$name" "$ip_v4" "$ip_v6" "$access" "$lan" "$v4" "$v6"

  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ansiutf8 < "$out" > "$OUT_CLIENTS/$name.qr.txt" || true
  fi
}

write_router_firewall_script() {
  local out="$OUT_ROUTER/firewall-router.sh"
  log "Writing router firewall script: ${out}"

  {
    echo '#!/bin/sh'
    echo 'set -eu'
    echo

    for iface in "${!IF_ENABLED[@]}"; do
      [[ "${IF_HOST[$iface]}" != "router" ]] && continue
      [[ "${IF_ENABLED[$iface]}" != "1" ]] && continue

      local chain="WG_${iface}"
      local chain6="WG6_${iface}"

      echo "# Interface ${iface}"
      echo "iptables  -N ${chain} 2>/dev/null || true"
      echo "iptables  -F ${chain}"
      echo "ip6tables -N ${chain6} 2>/dev/null || true"
      echo "ip6tables -F ${chain6}"
      echo

      # Base accept + NAT for this interface
      echo "iptables  -A ${chain}  -i ${iface} -j ACCEPT"
      echo "iptables  -A ${chain}  -o ${iface} -j ACCEPT"
      echo "iptables  -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
      echo "ip6tables -A ${chain6} -i ${iface} -j ACCEPT"
      echo "ip6tables -A ${chain6} -o ${iface} -j ACCEPT"
      echo

      # Per-client LAN blocking (internet-only)
      for entry in ${IF_CLIENTS_V4[$iface]:-}; do
        IFS=: read -r name ip lan <<<"$entry"
        [[ "$lan" = "1" ]] && continue
        echo "# ${name} IPv4 internet-only"
        echo "iptables -A ${chain} -i ${iface} -s ${ip}/32 -d 10.89.12.0/24 -j DROP"
      done

      for entry in ${IF_CLIENTS_V6[$iface]:-}; do
        IFS=: read -r name ip lan <<<"$entry"
        [[ "$lan" = "1" ]] && continue
        echo "# ${name} IPv6 internet-only"
        echo "ip6tables -A ${chain6} -i ${iface} -s ${ip}/128 -d fd89:7a3b:42c0::/64 -j DROP"
      done

      echo
      # Hook chains into FORWARD (idempotent per interface)
      cat <<EOF_IF
iptables  -C FORWARD -j ${chain}  2>/dev/null || iptables  -A FORWARD -j ${chain}
ip6tables -C FORWARD -j ${chain6} 2>/dev/null || ip6tables -A FORWARD -j ${chain6}
EOF_IF
      echo
    done
  } >"$out"

  chmod +x "$out"
}

write_nas_firewall_script() {
  local out="$OUT_SERVER/firewall-nas.sh"
  log "Writing NAS firewall script: ${out}"

  {
    echo '#!/bin/sh'
    echo 'set -eu'
    echo

    for iface in "${!IF_ENABLED[@]}"; do
      [[ "${IF_HOST[$iface]}" != "nas" ]] && continue
      [[ "${IF_ENABLED[$iface]}" != "1" ]] && continue

      local chain="WG_NAS_${iface}"
      local chain6="WG6_NAS_${iface}"

      echo "# Interface ${iface}"
      echo "iptables  -N ${chain} 2>/dev/null || true"
      echo "iptables  -F ${chain}"
      echo "ip6tables -N ${chain6} 2>/dev/null || true"
      echo "ip6tables -F ${chain6}"
      echo

      echo "iptables  -A ${chain}  -i ${iface} -j ACCEPT"
      echo "iptables  -A ${chain}  -o ${iface} -j ACCEPT"
      echo "ip6tables -A ${chain6} -i ${iface} -j ACCEPT"
      echo "ip6tables -A ${chain6} -o ${iface} -j ACCEPT"
      echo

      # Per-client LAN blocking (internet-only)
      for entry in ${IF_CLIENTS_V4[$iface]:-}; do
        IFS=: read -r name ip lan <<<"$entry"
        [[ "$lan" = "1" ]] && continue
        echo "# ${name} IPv4 internet-only"
        echo "iptables -A ${chain} -i ${iface} -s ${ip}/32 -d 10.89.12.0/24 -j DROP"
      done

      for entry in ${IF_CLIENTS_V6[$iface]:-}; do
        IFS=: read -r name ip lan <<<"$entry"
        [[ "$lan" = "1" ]] && continue
        echo "# ${name} IPv6 internet-only"
        echo "ip6tables -A ${chain6} -i ${iface} -s ${ip}/128 -d fd89:7a3b:42c0::/64 -j DROP"
      done

      echo
      # Hook chains into FORWARD (idempotent per interface)
      cat <<EOF_IF
iptables  -C FORWARD -j ${chain}  2>/dev/null || iptables  -A FORWARD -j ${chain}
ip6tables -C FORWARD -j ${chain6} 2>/dev/null || ip6tables -A FORWARD -j ${chain6}
EOF_IF
      echo
    done
  } >"$out"

  chmod +x "$out"
}

main() {
  log "Loading interfaces"
  load_interfaces

  log "Clearing previous output"
  rm -f "$OUT_SERVER"/*.conf "$OUT_ROUTER"/*.conf "$OUT_CLIENTS"/*.conf "$OUT_CLIENTS"/*.qr.txt || true

  for iface in "${!IF_ENABLED[@]}"; do
    if [[ "${IF_ENABLED[$iface]}" == "1" ]]; then
      write_server_config "$iface"
    fi
  done

  log "Processing clients"
  grep -vE '^(#|name)' "$CLIENTS_TSV" | while IFS=$'\t' read -r name device os iface access tunnel_mode lan v4 v6 dns_v4 dns_v6 notes; do
    [[ -z "$name" ]] && continue
    write_client_config "$iface" "$name" "$device" "$os" "$access" "$tunnel_mode" "$lan" "$v4" "$v6" "$dns_v4" "$dns_v6"
  done

  write_router_firewall_script
  write_nas_firewall_script

  log "Generation complete"
}

main "$@"
