#!/usr/bin/env bash
# /usr/local/bin/wg.sh — Unified WireGuard CLI
#
# Usage:
#   /usr/local/bin/wg.sh [--static] [--force] add <interface> <client> <profile> [email] [forced-ip]
#   /usr/local/bin/wg.sh clean
#   /usr/local/bin/wg.sh show
#   /usr/local/bin/wg.sh export <client> [interface]
#
# Interfaces:
#   wg-lan   → VPN interface for LAN-only access
#   wg-inet  → VPN interface with internet access
#
# Profiles:
#   lan-only   → access only the LAN
#   lan-inet   → access LAN + internet
#   inet-only  → internet only, no LAN
#
# Examples:
#   Add a laptop with LAN + internet access:
#       sudo /usr/local/bin/wg.sh add wg-inet elitebook lan-inet
#
#   Add a phone with LAN-only access and email tag:
#       sudo /usr/local/bin/wg.sh add wg-lan iphone lan-only user@example.com
#
#   Export an existing client config + QR:
#       sudo /usr/local/bin/wg.sh export elitebook
#
# Flags:
#   --static   Assign IP from .2–.10 (reserved range)
#   --force    Revoke any occupant and reassign specified IP
#
# Logging:
#   All events are written to the systemd journal under tag "wg-cli".
#   Inspect logs with:
#       journalctl -t wg-cli
#       journalctl -t wg-cli -f
#
# QR code PNGs (containing the full config + private key) are stored alongside client configs:
#   /etc/wireguard/clients/<interface>/<client>/<client>-key.png
# These files are root-only (chmod 600) because they expose the private key.

set -euo pipefail
trap 'logger -t wg-cli "❌ Unexpected error on line $LINENO"; exit 1' ERR

LOCKFILE="/var/lock/wg-cli.lock"

die() { logger -t wg-cli "❌ $*"; exit 1; }
log() { logger -t wg-cli "ℹ️ $*"; }

# --- Permissions ---
secure_file_private() { sudo chown root:root "$1" && sudo chmod 600 "$1"; }
secure_file_public()  { sudo chown root:root "$1" && sudo chmod 644 "$1"; }
secure_dir()          { sudo chown -R root:root "$1" && sudo chmod 700 "$1"; }

# --- Config ---
WG_CLIENTS_ROOT="/etc/wireguard/clients"
WG_ENDPOINT_DEFAULT="bardi.ch:51420"
LAN_ONLY_ALLOWED="10.89.12.0/24"
INET_ALLOWED="0.0.0.0/0, ::/0"
LAN_IPV4_PREFIX="10.4.0"
INET_IPV4_PREFIX="10.5.0"
LAN_IPV6_PREFIX="fd42:42:42::"
INET_IPV6_PREFIX="fd42:43:43::"

# --- Validation helpers ---
is_interface() { [[ "$1" == "wg-lan" || "$1" == "wg-inet" ]]; }
is_profile()   { [[ "$1" == "lan-only" || "$1" == "lan-inet" || "$1" == "inet-only" ]]; }
is_email()     { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
safe_name()    { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

normalize_email() {
  local email="${1:-}"
  [[ -z "$email" ]] && echo "none" && return
  is_email "$email" || die "Invalid email: $email"
  echo "$email"
}

# --- Paths ---
client_dir()  { echo "$WG_CLIENTS_ROOT/$1/$2"; }
client_pub()  { echo "$(client_dir "$1" "$2")/$2.pub"; }
client_key()  { echo "$(client_dir "$1" "$2")/$2.key"; }
client_conf() { echo "$(client_dir "$1" "$2")/$2.conf"; }
client_meta() { echo "$(client_dir "$1" "$2")/meta.txt"; }
exp_log()     { echo "$WG_CLIENTS_ROOT/expirations.log"; }

ensure_dirs() {
  sudo mkdir -p "$WG_CLIENTS_ROOT/wg-lan" "$WG_CLIENTS_ROOT/wg-inet"
  sudo touch "$(exp_log)"
  secure_file_private "$(exp_log)"
}

# --- IP assignment ---
next_free_octet() {
  local iface="$1" static="$2" used start end
  start=11; end=254
  [[ "$static" == "true" ]] && start=2 && end=10
  used=$(awk -F'|' -v iface="$iface" '$3==iface{split($2,a,"."); print a[4]}' "$(exp_log)" | sort -n | uniq)
  for i in $(seq "$start" "$end"); do
    grep -qw "$i" <<< "$used" || { echo "$i"; return 0; }
  done
  return 1
}

assign_ips() {
  local iface="$1" forced_ipv4="${2:-}" v4prefix v6prefix octet ipv4 ipv6
  v4prefix=$([[ "$iface" == "wg-lan" ]] && echo "$LAN_IPV4_PREFIX" || echo "$INET_IPV4_PREFIX")
  v6prefix=$([[ "$iface" == "wg-lan" ]] && echo "$LAN_IPV6_PREFIX" || echo "$INET_IPV6_PREFIX")
  if [[ -n "$forced_ipv4" ]]; then
    octet=$(awk -F'.' '{print $4}' <<< "$forced_ipv4")
  else
    octet=$(next_free_octet "$iface" "$STATIC") || die "No free IPs in $iface"
  fi
  ipv4="$v4prefix.$octet"
  ipv6="${v6prefix}${octet}"
  echo "$ipv4|$ipv6"
}

profile_apply() {
  case "$1" in
    lan-only)  echo "$LAN_ONLY_ALLOWED|10.89.12.4|never" ;;
    lan-inet)  echo "$INET_ALLOWED|10.89.12.4,1.1.1.1,8.8.8.8|never" ;;
    inet-only) echo "$INET_ALLOWED|10.89.12.4,1.1.1.1,8.8.8.8|$(date -d '+1 year' +'%Y-%m-%d')" ;;
  esac
}

# --- Commands ---
cmd_add() {
  ensure_dirs
  local iface="$1" client="$2" profile="$3" email="${4:-}" forced_ip="${5:-}"
  is_interface "$iface" || die "Invalid interface: $iface"
  is_profile "$profile" || die "Invalid profile: $profile"
  safe_name "$client"   || die "Unsafe client name"
  email="$(normalize_email "$email")"

  local cdir="$(client_dir "$iface" "$client")"
  local pub="$(client_pub "$iface" "$client")"
  local key="$(client_key "$iface" "$client")"
  local conf="$(client_conf "$iface" "$client")"
  local meta="$(client_meta "$iface" "$client")"
  local srv_pub="/etc/wireguard/$iface.pub"

  [[ -e "$cdir" ]] && die "Client already exists: $client on $iface"
  [[ -f "$srv_pub" ]] || die "Missing server public key: $srv_pub
➡️ Generate it with:
   umask 077
   wg genkey | tee /etc/wireguard/$iface.key | wg pubkey > /etc/wireguard/$iface.pub"

  sudo mkdir -p "$cdir"; secure_dir "$cdir"

  { flock -x 200 || exit 1
    IFS='|' read -r ip ipv6 <<< "$(assign_ips "$iface" "$forced_ip")"
    log "Assigning $client on $iface → IPv4 $ip, IPv6 $ipv6"

    sudo bash -c "wg genkey | tee '$key' | wg pubkey > '$pub'"
    secure_file_private "$key"
    secure_file_public "$pub"

    IFS='|' read -r allowed dns expiry <<< "$(profile_apply "$profile")"
    sudo tee "$conf" >/dev/null <<EOF
[Interface]
Address = $ip/32,$ipv6/128
PrivateKey = $(<"$key")
DNS = $dns
MTU = 1420

[Peer]
PublicKey = $(<"$srv_pub")
Endpoint = $WG_ENDPOINT_DEFAULT
AllowedIPs = $allowed
PersistentKeepalive = 25
EOF
    secure_file_private "$conf"

    sudo tee "$meta" >/dev/null <<EOF
Client: $client
Interface: $iface
IP: $ip
IPv6: $ipv6
Profile: $profile
Email: $email
Allowed: $allowed
DNS: $dns
Created: $(date -Iseconds)
Expires: $expiry
EOF
    secure_file_public "$meta"

    echo "$client | $ip | $iface | $profile | $email | Expires: $expiry" | sudo tee -a "$(exp_log)" >/dev/null
  } 200>"$LOCKFILE"

  echo "📱 Scan this QR code with your WireGuard mobile app:"
  qrencode -t ansiutf8 < "$conf"
  qrencode -o "$(dirname "$conf")/${client}-key.png" < "$conf"
  secure_file_private "$(dirname "$conf")/${client}-key.png"
  log "Saved QR code PNG at $(dirname "$conf")/${client}-key.png"
}

cmd_show() {
  ensure_dirs
  printf "%-15s %-10s %-15s %-25s %-20s %-20s\n" "Client" "Iface" "IP" "Profile" "Last Handshake" "RX/TX"
  printf "%-15s %-10s %-15s %-25s %-20s %-20s\n" "------" "-----" "----" "-------" "--------------" "-----"
  while IFS='|' read -r client ip iface profile email rest; do
    [[ -z "$client" ]] && continue
    local pub="$(client_pub "$iface" "$client")"
    [[ -f "$pub" ]] || continue
    local line
    line=$(sudo wg show "$iface" dump | awk -v pub="$(<"$pub")" '$1==pub {print $0}')
    if [[ -n "$line" ]]; then
      IFS=$'\t' read -r _ _ _ _ _ _ last rx tx _ <<< "$line"
      printf "%-15s %-10s %-15s %-25s %-20s %-20s\n" "$client" "$iface" "$ip" "$profile" "$last" "$rx/$tx"
    else
      printf "%-15s %-10s %-15s %-25s %-20s %-20s\n" "$client" "$iface" "$ip" "$profile" "—" "—"
    fi
  done < "$(exp_log)"
}

cmd_export() {
  local client="$1" iface="${2:-}"
  [[ -z "$client" ]] && die "Usage: wg.sh export <client> [interface]"
  local cdir
  if [[ -n "$iface" ]]; then
    cdir="$(client_dir "$iface" "$client")"
  else
    cdir=$(find "$WG_CLIENTS_ROOT" -maxdepth 2 -type d -name "$client" 2>/dev/null | head -n1)
  fi
  [[ -d "$cdir" ]] || die "Client not found: $client"
  local conf="$cdir/$client.conf"
  [[ -f "$conf" ]] || die "Missing config for $client"
  cat "$conf"
  echo "📱 QR code:"
  qrencode -t ansiutf8 < "$conf"
  qrencode -o "$cdir/${client}-key.png" < "$conf"
  secure_file_private "$cdir/${client}-key.png"
  log "Re-saved QR code PNG at $cdir/${client}-key.png"
}

cmd_clean() {
  ensure_dirs
  local now=$(date +%s)
  local tmp=$(mktemp)
  while IFS='|' read -r client ip iface profile email rest; do
    [[ -z "$client" ]] && continue
    local expiry=$(awk -F'Expires: ' '{print $2}' <<< "$rest")
    if [[ "$expiry" != "never" ]]; then
      local exp_ts=$(date -d "$expiry" +%s)
      if (( exp_ts < now )); then
        log "Cleaning expired client $client ($iface)"
        sudo rm -rf "$(client_dir "$iface" "$client")"
        continue
      fi
    fi
    echo "$client | $ip | $iface | $profile | $email | Expires: $expiry" >> "$tmp"
  done < "$(exp_log)"
  sudo mv "$tmp" "$(exp_log)"
  secure_file_private "$(exp_log)"
}

# --- Main dispatcher ---
STATIC="false"
FORCE="false"
while [[ "${1:-}" =~ ^-- ]]; do
  case "$1" in
    --static) STATIC="true";;
    --force)  FORCE="true";;
    *) die "Unknown flag: $1";;
  esac
  shift
done

cmd="${1:-}"; shift || true
case "$cmd" in
  add)    cmd_add "$@";;
  show)   cmd_show "$@";;
  export) cmd_export "$@";;
  clean)  cmd_clean "$@";;
  *) die "Usage: /usr/local/bin/wg.sh [--static] [--force] {add|show|export|clean} …";;
esac
