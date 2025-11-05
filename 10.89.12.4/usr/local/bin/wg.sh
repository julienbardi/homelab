#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- Constants ---
LAN_ONLY_ALLOWED="10.89.12.0/24"
INET_ALLOWED="0.0.0.0/0"
WG_DIR="/etc/wireguard"
CLIENT_DIR="$WG_DIR/clients"
DASHBOARD="/var/www/html/wg-dashboard/index.html"

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
#
# Notes:
# - IPv4‑only profiles (wg1–wg3) are safe defaults, no special client action.
# - wg0 is a null profile: useful for testing that no traffic passes.
# - IPv6‑enabled profiles (wg4–wg7) work fine on Linux, Android, iOS.
# - On Windows, IPv6‑enabled profiles (wg4–wg7) may leak traffic over LAN IPv6
#   because Windows prefers IPv6 routes. To prevent this, always run
#   fix-wireguard-routing.ps1 when using wg4–wg7.
# --------------------------------------------------------------------

show_helper() {
  cat <<'EOF'
WireGuard management helper script

Usage:
  /usr/local/bin/wg.sh [--static] [--force] add <iface> <client> [email] [forced-ip]
  /usr/local/bin/wg.sh clean
  /usr/local/bin/wg.sh show
  /usr/local/bin/wg.sh export <client> [iface]
  /usr/local/bin/wg.sh --helper

Profiles:
  wg0 → Null profile (no access, testing only)
  wg1 → LAN only (IPv4)
  wg2 → Internet only (IPv4)
  wg3 → LAN + Internet (IPv4)
  wg4 → IPv6 only (* Windows: run fix-wireguard-routing.ps1)
  wg5 → LAN (IPv4) + IPv6 (* Windows: run fix-wireguard-routing.ps1)
  wg6 → Internet (IPv4) + IPv6 (* Windows: run fix-wireguard-routing.ps1)
  wg7 → LAN + Internet + IPv6 (* Windows: run fix-wireguard-routing.ps1)

Flags:
  --static   Assign IP from reserved static range
  --force    Revoke any occupant and reassign specified IP
  --helper   Show this help and profile mapping

Windows users:
  For wg4–wg7, always run fix-wireguard-routing.ps1 AFTER connecting.
  You may re-run it while VPN is active if routes reset.
  Do NOT run before connecting. No need after disconnecting.
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
  else
    die "Interface $raw encodes no supported access policy"
  fi
}
cmd_show() {
  echo "=== WireGuard status ==="
  wg show
  echo
  echo "=== Active interfaces ==="
  wg show interfaces
  echo
  echo "=== Peers per interface ==="
  for iface in $(wg show interfaces); do
    echo "[$iface]"
    wg show "$iface" peers
    echo
  done
}

cmd_clean() {
  echo "Cleaning up stale WireGuard peers..."
  # Example: remove peers with expired configs
  # (Adapt this logic to your environment)
  wg show | grep 'peer' || echo "No peers found."
}

cmd_export() {
  local client="$1"
  local iface="${2:-}"
  echo "Exporting configuration for client '$client' ${iface:+on $iface}..."
  cat "$CLIENT_DIR/${client}${iface:+-$iface}.conf" 2>/dev/null \
    || echo "No config found for $client $iface"
}

cmd_add() {
  local iface="$1"
  local client="$2"
  local email="${3:-}"
  local forced_ip="${4:-}"

  IFS='|' read -r allowed dns expiry label <<< "$(policy_for_iface "$iface")"

  # Generate keys
  privkey=$(wg genkey)
  pubkey=$(echo "$privkey" | wg pubkey)

  # Assign IP
  if [[ -n "$forced_ip" ]]; then
    ip="$forced_ip"
  else
    ip="10.89.12.$((RANDOM % 200 + 20))"
  fi

  # Write client config
  mkdir -p "$CLIENT_DIR"
  cfg="$CLIENT_DIR/${client}-${iface}.conf"
  cat >"$cfg" <<EOF
[Interface]
PrivateKey = $privkey
Address = $ip/32
DNS = $dns

[Peer]
PublicKey = $(cat $WG_DIR/$iface.pub)
AllowedIPs = $allowed
Endpoint = vpn.example.com:
  Endpoint = vpn.example.com:51820
  PersistentKeepalive = 25
EOF

  echo "Client config written to $cfg"

  # Add peer to server
  wg set "$iface" peer "$pubkey" allowed-ips "$ip/32"

  # Generate QR code for mobile clients
  qrencode -t ansiutf8 < "$cfg"

  # Update dashboard
  if [[ -f "$DASHBOARD" ]]; then
    echo "Updating dashboard..."
    sed -i "/<\/tbody>/i <tr><td>$client</td><td>$iface</td><td>$ip</td><td>$expiry</td></tr>" "$DASHBOARD"
  fi

  # Send email if address provided
  if [[ -n "$email" ]]; then
    echo "Sending config to $email..."
    {
      echo "Subject: WireGuard VPN configuration for $client"
      echo
      echo "Hello $client,"
      echo
      echo "Attached is your WireGuard VPN configuration for interface $iface."
      echo "Allowed IPs: $allowed"
      echo "DNS: $dns"
      echo "Expiry: $expiry"
      echo
      echo "Regards,"
      echo "VPN Admin"
    } | sendmail "$email"
  fi

  # Advisory for IPv6 profiles
  if [[ "$label" == *"IPv6"* ]]; then
    echo "⚠️  IPv6 support enabled for $client on $iface"
    echo "   • Windows: run fix-wireguard-routing.ps1 when using wg4–wg7."
    echo "     Run AFTER connecting, may re-run while active, not before/after disconnect."
    echo "   • Linux/Android/iOS: no action needed."
  fi
}
# --- Main dispatcher ---
case "${1:-}" in
  --helper) show_helper; exit 0 ;;
  add) shift; cmd_add "$@" ;;
  clean) shift; cmd_clean "$@" ;;
  show) shift; cmd_show "$@" ;;
  export) shift; cmd_export "$@" ;;
  "" )
    # No arguments → show help
    show_helper
    exit 0
    ;;
  * )
    echo "Unknown command: $1" >&2
    show_helper
    exit 1
    ;;
esac
