#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- Constants ---
SERVER_IP="10.89.12.4"
SERVER_MTU=1420
LAN_ONLY_ALLOWED="10.89.12.0/24"
INET_ALLOWED="0.0.0.0/0"
WG_DIR="/etc/wireguard"
CLIENT_DIR="$WG_DIR/clients"
DASHBOARD="/var/www/html/wg-dashboard/index.html"
SUBNET="10.89.12"
STATIC_START=1
STATIC_END=100
DYNAMIC_START=101
DYNAMIC_END=254

# --------------------------------------------------------------------
# Interface mapping (bitmask scheme)
#
# Bits:
#   Bit 1 (value 1) → LAN access (IPv4)
#   Bit 2 (value 2) → Internet access (IPv4)
#   Bit 3 (value 4) → IPv6 access (::/0)
#
# Truth table:
#   Interface | Bits (lan,inet,ipv6) | Meaning                                | Windows note
#   ----------+----------------------+----------------------------------------+-------------------------------
#   wg0       | 000                  | Null profile (no access, testing only) | -
#   wg1       | 001                  | LAN only (IPv4)                        | -
#   wg2       | 010                  | Internet only (IPv4)                   | -
#   wg3       | 011                  | LAN + Internet (IPv4)                  | -
#   wg4 *     | 100                  | IPv6 only (rarely useful)              | * May cause routing issues
#   wg5 *     | 101                  | LAN (IPv4) + IPv6                      | * May cause routing issues
#   wg6 *     | 110                  | Internet (IPv4) + IPv6                 | * May cause routing issues
#   wg7 *     | 111                  | LAN + Internet + IPv6 (full tunnel)    | * May cause routing issues
# --------------------------------------------------------------------

show_helper() {
  cat <<'EOF'
WireGuard management helper script

Usage:
  /usr/local/bin/wg.sh add <iface> <client> [email] [forced-ip]
  /usr/local/bin/wg.sh clean <iface>
  /usr/local/bin/wg.sh show
  /usr/local/bin/wg.sh export <client> [iface]
  /usr/local/bin/wg.sh --helper
EOF
}
policy_for_iface() {
  local raw="$1"
  [[ "$raw" =~ ^wg([0-9]+)$ ]] || die "Invalid interface name: $raw"
  local num="${BASH_REMATCH[1]}"

  local lan=$(( num & 1 ))
  local inet=$(( (num >> 1) & 1 ))
  local ipv6=$(( (num >> 2) & 1 ))

  if [[ $num -eq 0 ]]; then
    echo "| |never|Null profile (no access)"
  elif [[ $lan -eq 1 && $inet -eq 0 && $ipv6 -eq 0 ]]; then
    echo "$LAN_ONLY_ALLOWED|10.89.12.4|never|LAN only (IPv4)"
  elif [[ $lan -eq 0 && $inet -eq 1 && $ipv6 -eq 0 ]]; then
    echo "$INET_ALLOWED|1.1.1.1,8.8.8.8|$(date -d '+1 year' +'%Y-%m-%d')|Internet only (IPv4)"
  elif [[ $lan -eq 1 && $inet -eq 1 && $ipv6 -eq 0 ]]; then
    echo "$INET_ALLOWED|10.89.12.4,1.1.1.1,8.8.8.8|never|LAN + Internet (IPv4)"
  elif [[ $lan -eq 0 && $inet -eq 0 && $ipv6 -eq 1 ]]; then
    echo "::/0|2606:4700:4700::1111|never|IPv6 only"
  elif [[ $lan -eq 1 && $inet -eq 0 && $ipv6 -eq 1 ]]; then
    echo "$LAN_ONLY_ALLOWED,::/0|10.89.12.4,2606:4700:4700::1111|never|LAN + IPv6"
  elif [[ $lan -eq 0 && $inet -eq 1 && $ipv6 -eq 1 ]]; then
    echo "$INET_ALLOWED,::/0|1.1.1.1,8.8.8.8,2606:4700:4700::1111|never|Internet + IPv6"
  elif [[ $lan -eq 1 && $inet -eq 1 && $ipv6 -eq 1 ]]; then
    echo "$INET_ALLOWED,::/0|10.89.12.4,1.1.1.1,8.8.8.8,2606:4700:4700::1111|never|LAN + Internet + IPv6"
  fi
}

allocate_ip() {
  # Collect all used IPs across all interfaces
  used=$(wg show all allowed-ips | awk '{print $2}' | cut -d/ -f1)
  for i in $(seq $DYNAMIC_START $DYNAMIC_END); do
    candidate="$SUBNET.$i"
    if ! grep -q "$candidate" <<< "$used"; then
      echo "$candidate"
      return
    fi
  done
  die "No free IPs available"
}

cmd_show() {
  echo "=== WireGuard Interfaces ==="
  {
    echo -e "🔌 IFACE\t🔑 PUBLIC-KEY\t📡 LISTEN-PORT\t🖧 ADDR(v4)\t🖧 ADDR(v6)"
    for iface in $(wg show interfaces); do
      pub=$(wg show "$iface" public-key)
      port=$(wg show "$iface" listen-port)
      addr4=$(ip -o -4 addr show dev "$iface" | awk '{print $4}' | paste -sd "," -)
      addr6=$(ip -o -6 addr show dev "$iface" | awk '{print $4}' | paste -sd "," -)
      echo -e "$iface\t${pub:0:20}…\t$port\t${addr4:-"-"}\t${addr6:-"-"}"
    done
  } | column -t -s $'\t'

  echo
  echo "=== WireGuard Peers ==="
  {
    echo -e "🔌 IFACE\t👤 NAME\t🔑 PEER-PUBKEY\t🌐 ALLOWED-IPS\t📡 ENDPOINT\t⏱️ HANDSHAKE\t⬆️ TX\t⬇️ RX\tSTATUS"
    now=$(date +%s)
    for iface in $(wg show interfaces); do
      for peer in $(wg show "$iface" peers); do
        allowed=$(wg show "$iface" allowed-ips | awk -v p="$peer" '$1==p {print $2}')
        endpoint=$(wg show "$iface" endpoints | awk -v p="$peer" '$1==p {print $2}')
        handshake=$(wg show "$iface" latest-handshakes | awk -v p="$peer" '$1==p {print $2}')
        transfer=$(wg show "$iface" transfer | awk -v p="$peer" '$1==p {print $2" "$3" / "$4" "$5}')

        # Map pubkey → client name
        match=$(grep -l "$peer" "$CLIENT_DIR"/*-"$iface".conf 2>/dev/null | head -n1)
        if [[ -n "$match" ]]; then
          peer_name=$(basename "$match" | cut -d- -f1)
        else
          peer_name="?"
        fi

        # Handshake formatting + status
        if [[ "$handshake" -eq 0 ]]; then
          hstr="never"
          status="❌"
        else
          hstr="$(date -d @"$handshake" '+%Y-%m-%d %H:%M:%S')"
          age=$(( now - handshake ))
          if (( age < 120 )); then
            status="✅"
          else
            status="❌"
          fi
        fi

        tx=$(echo "$transfer" | cut -d/ -f1)
        rx=$(echo "$transfer" | cut -d/ -f2)

        echo -e "$iface\t$peer_name\t${peer:0:20}…\t$allowed\t$endpoint\t$hstr\t$tx\t$rx\t$status"
      done
    done
  } | column -t -s $'\t'
}

cmd_clean() {
  local iface="$1"
  echo "Removing all peers from $iface..."
  for peer in $(wg show "$iface" peers); do
    wg set "$iface" peer "$peer" remove
  done
}

cmd_export() {
  local client="$1"
  local iface="${2:-}"
  cat "$CLIENT_DIR/${client}${iface:+-$iface}.conf" 2>/dev/null \
    || echo "No config found for $client $iface"
}

cmd_add() {
  local iface="$1"
  local client="$2"
  local email="${3:-}"
  local forced_ip="${4:-}"

  IFS='|' read -r allowed dns expiry label <<< "$(policy_for_iface "$iface")"

  # --- Check server key exists ---
  if [[ ! -f "$WG_DIR/$iface.pub" ]]; then
    echo -e "❌ Missing server public key: $WG_DIR/$iface.pub\n\
To fix, copy and paste the following commands:\n\
  sudo /usr/bin/wg genkey | sudo tee $WG_DIR/$iface.key | sudo /usr/bin/wg pubkey | sudo tee $WG_DIR/$iface.pub > /dev/null\n\
  sudo chown root:root $WG_DIR/$iface.key $WG_DIR/$iface.pub\n\
  sudo chmod 600 $WG_DIR/$iface.key\n\
  sudo chmod 644 $WG_DIR/$iface.pub"
    exit 1
  fi

  # --- Ensure server config exists ---
  if [[ ! -f "$WG_DIR/$iface.conf" ]]; then
    echo "⚙️  Creating base config for $iface at $WG_DIR/$iface.conf"
    port=$((51420 + ${iface#wg}))

    cat > "$WG_DIR/$iface.conf" <<EOF
[Interface]
PrivateKey = $(cat "$WG_DIR/$iface.key")
Address = $SERVER_IP/24
ListenPort = $port
MTU = $SERVER_MTU
EOF

    chmod 600 "$WG_DIR/$iface.conf"
    chown root:root "$WG_DIR/$iface.conf"

    wg-quick up "$iface"
  fi

  # --- Generate client keys ---
  privkey=$(wg genkey)
  pubkey=$(echo "$privkey" | wg pubkey)

  # --- Allocate IP ---
  if [[ -n "$forced_ip" ]]; then
    ip="$forced_ip"
  else
    ip=$(allocate_ip)
  fi

  mkdir -p "$CLIENT_DIR"
  cfg="$CLIENT_DIR/${client}-${iface}.conf"
  port=$((51420 + ${iface#wg}))

  cat >"$cfg" <<EOF
[Interface]
PrivateKey = $privkey
Address = $ip/32
DNS = $dns
MTU = $SERVER_MTU

[Peer]
PublicKey = $(cat $WG_DIR/$iface.pub)
AllowedIPs = $allowed
Endpoint = bardi.ch:$port
PersistentKeepalive = 25
EOF

  wg set "$iface" peer "$pubkey" allowed-ips "$ip/32"
  # --- Persist peer in server config ---
  cat >> "$WG_DIR/$iface.conf" <<EOF
  
[Peer]
# $client
PublicKey = $pubkey
AllowedIPs = $ip/32
EOF

  qrencode -t ansiutf8 < "$cfg"

  if [[ -f "$DASHBOARD" ]]; then
    sed -i "/<\/tbody>/i <tr><td>$client</td><td>$iface</td><td>$ip</td><td>$expiry</td></tr>" "$DASHBOARD"
  fi

  if [[ -n "$email" ]]; then
    echo "ℹ️  Email address $email was provided, but email sending is disabled."
    echo "    The configuration file is available at: $cfg"
  fi

  # Always show where the config was saved
  echo "ℹ️  Client config saved at: $cfg"
  echo "   View it with: sudo /usr/local/bin/wg.sh export $client $iface"
}

case "${1:-}" in
  --helper) show_helper; exit 0 ;;
  add) shift; cmd_add "$@" ;;
  clean) shift; cmd_clean "$@" ;;
  show) shift; cmd_show "$@" ;;
  export) shift; cmd_export "$@" ;;
  "" ) show_helper; exit 0 ;;
  * ) echo "Unknown command: $1" >&2; show_helper; exit 1 ;;
esac
