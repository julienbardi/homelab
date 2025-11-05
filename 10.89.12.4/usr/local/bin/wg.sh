#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- Constants ---
LAN_ONLY_ALLOWED="10.89.12.0/24"
INET_ALLOWED="0.0.0.0/0"
WG_DIR="/etc/wireguard"
CLIENT_DIR="$WG_DIR/clients"
DASHBOARD="/var/www/html/wg-dashboard/index.html"
SUBNET="10.89.12"
STATIC_START=1
STATIC_END=10
DYNAMIC_START=11
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
  wg show
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
    echo "❌ Missing server public key: $WG_DIR/$iface.pub"
    echo "To fix, run the following commands:"
    echo "  /usr/bin/wg genkey | tee $WG_DIR/$iface.key | /usr/bin/wg pubkey > $WG_DIR/$iface.pub"
    echo "  chown root:root $WG_DIR/$iface.key $WG_DIR/$iface.pub"
    echo "  chmod 600 $WG_DIR/$iface.key"
    echo "  chmod 644 $WG_DIR/$iface.pub"
    exit 1
  fi
  
  # Generate client keys
  privkey=$(wg genkey)
  pubkey=$(echo "$privkey" | wg pubkey)

  # Allocate IP
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

[Peer]
PublicKey = $(cat $WG_DIR/$iface.pub)
AllowedIPs = $allowed
Endpoint = bardi.ch:$port
PersistentKeepalive = 25
EOF

  wg set "$iface" peer "$pubkey" allowed-ips "$ip/32"

  qrencode -t ansiutf8 < "$cfg"

  if [[ -f "$DASHBOARD" ]]; then
    sed -i "/<\/tbody>/i <tr><td>$client</td><td>$iface</td><td>$ip</td><td>$expiry</td></tr>" "$DASHBOARD"
  fi

  if [[ -n "$email" ]]; then
    {
      echo "Subject: WireGuard VPN configuration for $client"
      echo
      cat "$cfg"
    } | sendmail "$email"
  fi
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
