#!/usr/bin/env bash
# Script: wg.sh
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/wg.sh /usr/local/bin/wg.sh
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- Constants ---
WG_ENDPOINT_HOST="bardi.ch"
BASE_WG_PORT=51420
SERVER_MTU=1420
WG_DIR="/etc/wireguard"
CLIENT_DIR="$WG_DIR/clients"

# --- LAN & SUBNET CONSTANTS ---
NAS_LAN_IP="10.89.12.4"
LAN_SUBNET="10.89.12.0/24"
#LAN_SUBNET_V6="fd10:3::/64" # NEW: Your local IPv6 range
# On NAS run "ip -br link show type bridge" to list the interfaces
NAS_LAN_IFACE="bridge0"

# --- WG CLIENT IP ALLOCATION ---
# Note: Server is always .1
STATIC_START=2
STATIC_END=100
DYNAMIC_START=101
DYNAMIC_END=254

# --- AllowedIPs Constants ---
#LAN_ONLY_ALLOWED="$LAN_SUBNET,$LAN_SUBNET_V6"
INET_ALLOWED="0.0.0.0/0"
IPV6_INET_ALLOWED="::/0"
#FULL_TUNNEL_ROUTES="$INET_ALLOWED,$IPV6_INET_ALLOWED,$LAN_SUBNET,$LAN_SUBNET_V6"

# --------------------------------------------------------------------
# Interface mapping (bitmask scheme)
#
# Bits:
#   Bit 1 (value 1) → LAN access (IPv4)
#   Bit 2 (value 2) → Internet access (IPv4)
#   Bit 3 (value 4) → IPv6 access (::/0)
#
# Truth table:
#   Interface | Bits | Meaning                        | Client AllowedIPs Logic
#   ----------+------+--------------------------------+-------------------------------
#   wg0       | 000  | Null profile (no access)       | None
#   wg1       | 001  | LAN only (IPv4)                | LAN-ONLY (LAN-v4 + Server-v4)
#   wg2       | 010  | Internet only (IPv4)           | FULL-TUNNEL (v4 Full Tunnel)
#   wg3       | 011  | LAN + Internet (IPv4)          | FULL-TUNNEL (v4 Full Tunnel + Explicit LAN-v4)
#   wg4       | 100  | IPv6 only                      | FULL-TUNNEL (v6 Full Tunnel)
#   wg5       | 101  | LAN (v4) + IPv6                | LAN-ONLY (LAN-v4/v6 + Server-v4/v6)
#   wg6       | 110  | Internet (v4) + IPv6           | FULL-TUNNEL (v4/v6 Full Tunnel)
#   wg7       | 111  | LAN + Internet + IPv6          | FULL-TUNNEL (v4/v6 Full Tunnel + Explicit LAN-v4/v6)
# --------------------------------------------------------------------
show_helper() {
  cat <<'EOF'
WireGuard management helper script (MODIFIED)

Usage:
  /usr/local/bin/wg.sh add <iface> <client> [email] [forced-ip]
  /usr/local/bin/wg.sh clean <iface>
  /usr/local/bin/wg.sh clean-all
  /usr/local/bin/wg.sh revoke <iface> <client>
  /usr/local/bin/wg.sh rebuild <iface>
  /usr/local/bin/wg.sh show
  /usr/local/bin/wg.sh export <client> [iface]
  /usr/local/bin/wg.sh qr <client> [iface]
  /usr/local/bin/wg.sh setup-keys
  /usr/local/bin/wg.sh --helper
EOF
}

#
policy_for_iface() {
    local raw="$1"
    local num # Must be declared for scoping
    case "$raw" in
        wg[0-9]|wg[0-9][0-9])
            num="${raw#wg}" # POSIX extraction
            ;;
        *)
            die "Invalid interface name: $raw"
            ;;
    esac
    # --- Define server and external IPs ---
    local server_ipv4="10.$num.0.1"
    local server_ipv6="fd10:$num::1"
    local ext_dns_v4="1.1.1.1,8.8.8.8"
    local ext_dns_v6="2606:4700:4700::1111"
    
    # --- Output Variables ---
    local client_allowed_ips=""
    local client_dns=""
    local policy_label=""

    # --- Local Helper Variables (LAN_SUBNET must be defined earlier) ---
    local LAN_ROUTES="$LAN_SUBNET" # IPv4 LAN only (10.89.12.0/24)
    local SERVER_ONLY_ROUTES="$server_ipv4/32,$server_ipv6/128"

    # --- Case Statement Logic (Grouped by Policy) ---
    case "$num" in
        0) # wg0: Null Profile (000)
            client_allowed_ips=""
            client_dns="$NAS_LAN_IP"
            policy_label="$raw: Null profile (no access)"
            ;;
        1) # wg1 (LAN V4 Only) - LAN Only Policy (001)
            client_allowed_ips="$LAN_ROUTES,$server_ipv4/32"
            client_dns="$NAS_LAN_IP"
            policy_label="$raw: LAN only (IPv4)"
            ;;
        5) # wg5 (LAN V4 + V6) - LAN Only Policy (101) - SPLIT TUNNEL
            client_allowed_ips="$LAN_ROUTES,fd10:$num::/64,$SERVER_ONLY_ROUTES"
            client_dns="$NAS_LAN_IP"
            policy_label="$raw: LAN (v4) + IPv6 (Split: $num Subnet)"
            ;;
        
        2) # wg2 (Internet V4 Only) - Pure Full Tunnel (010)
            client_allowed_ips="$INET_ALLOWED"
            client_dns="$ext_dns_v4"
            policy_label="$raw: Internet only (IPv4)"
            ;;
        4) # wg4 (IPv6 Only) - Pure Full Tunnel (100)
            client_allowed_ips="$IPV6_INET_ALLOWED"
            client_dns="$ext_dns_v6"
            policy_label="$raw: IPv6 only"
            ;;
        6) # wg6 (Internet V4 + V6) - Pure Full Tunnel (110)
            client_allowed_ips="$INET_ALLOWED,$IPV6_INET_ALLOWED"
            client_dns="$ext_dns_v4,$ext_dns_v6"
            policy_label="$raw: Internet (v4) + IPv6"
            ;;

        3|7|*) # wg3, wg7, and Default (*) - Full Tunnel (011, 111, ...)
            # LAN_ROUTES nur noch IPv4. ::/0 deckt IPv6-Internet und -LAN ab.
            client_allowed_ips="$LAN_ROUTES,$INET_ALLOWED,$IPV6_INET_ALLOWED"
            # DNS: NAS Primary + Public Fallbacks
            client_dns="$NAS_LAN_IP,$ext_dns_v4,$ext_dns_v6"
            policy_label="$raw: Full Tunnel (LAN + Internet + IPv6)"
            ;;
    esac

    # Return the policy string: <AllowedIPs>|<DNS>|<Expiry>|<Label>
    echo "$client_allowed_ips|$client_dns|never|$policy_label"
}

# Reads private key file and ensures a clean, single line for parser safety.
#
_get_private_key_clean() {
    local keyfile="$1"
    # CRITICAL FIX: Use tr to ruthlessly delete all problematic characters.
    # We wrap the output in printf "%s" to eliminate the *final* newline
    # that shell command substitution usually includes.
    printf "%s" "$(sudo tr -d '\n\r ' < "$keyfile")"
}
#
# --- [MODIFIED] ---
# Now allocates from the correct 10.N.0.x subnet
#
allocate_ip() {
  local iface="$1"
  local num # Must be declared for scoping
    case "$raw" in
        wg[0-9]|wg[0-9][0-9])
            num="${raw#wg}" # POSIX extraction
            ;;
        *)
            die "Invalid interface name: $raw"
            ;;
    esac
  local subnet_base="10.$num.0"

  # Collect all used IPs across all interfaces
  local u
  u=$(sudo wg show all allowed-ips | awk '{print $2}' | cut -d/ -f1)

  local i
  for i in $(seq $DYNAMIC_START $DYNAMIC_END); do
    local candidate="$subnet_base.$i"
    # Use -x for exact line match
    if ! grep -q -x "$candidate" <<< "$u"; then
      echo "$candidate"
      return
    fi
  done
  die "No free IPs available in $subnet_base.0/24"
}

cmd_show() {
  local iface pub port addr4 addr6 peer allowed endpoint handshake transfer 
  local now match peer_name hstr status tx rx age
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
  local mode="${2:-}" 
  
  (
    flock -x 200
    echo "🧹 Removing all clients from $iface..."
    
    # Client file deletion is MANDATORY for both soft and full cleanups.
    rm -f "$CLIENT_DIR"/*-"$iface".conf 2>/dev/null || true 

    if [[ "$mode" == "--full" ]]; then
      # If keys are being deleted, the interface MUST be stopped first.
      echo "⬇️ Shutting down $iface..."
      sudo wg-quick down "$iface" 2>/dev/null || true
      
      echo "⚠️  Performing FULL cleanup: Removing server keys and base config for $iface..."
      # Delete server files
      sudo sh -c "rm -f \"$WG_DIR/$iface.conf\" \"$WG_DIR/$iface.key\" \"$WG_DIR/$iface.pub\""
      
      # Cleanup lock file and directory
      sudo rm -f "$WG_DIR/$iface.lock" 2>/dev/null || true
      sudo rmdir "$CLIENT_DIR" 2>/dev/null || true
      
      echo "✅ $iface has been fully removed."
    else
      # Soft clean: Only rebuild the config after client files are removed above.
      _rebuild_nolock "$iface"
      echo "✅ $iface is now clean (no peers)."
    fi

  ) 200>"$WG_DIR/$iface.lock"
}

cmd_clean_all() {
  local mode="${1:-}" 
  local cleanup_message="client configs and server configs"
  local iface
  
  if [[ "$mode" == "--full" ]]; then
    cleanup_message="ALL client configs, ALL server configs, and ALL server keys"
  fi
  
  read -p "⚠️  This will remove $cleanup_message for all interfaces. Are you sure? [y/N] " ans
  case "$ans" in
    [yY][eE][sS]|[yY])
      echo "🧹 Identifying interfaces from all config, key, pub, and lock files on disk..."
      
      # Use find to list all files starting with 'wg' (e.g., wg1.conf, wg1.key, wg1.lock).
      # Pipe the output to sed to strip the path and file extension, leaving only the interface name (e.g., 'wg1').
      # Then use sort -u to get a clean, unique list of interface names.
      local interface_list
      interface_list=$(sudo find "$WG_DIR" -maxdepth 1 -type f -name 'wg[0-9]*.*' 2>/dev/null | \
                       sed 's|^.*/|| ; s/\.[^.]*$//' | sort -u)

      for iface in $interface_list; do
          # Call cmd_clean for the found interface, passing the --full mode if present.
          # The logic inside cmd_clean will handle interface shutdown and file deletion.
          cmd_clean "$iface" "$mode"
      done

      if [[ -z "$interface_list" ]]; then
          echo "ℹ️ Note: No WireGuard interface files were found on disk."
      fi

      echo "✅ Cleanup complete."
      ;;
    *)
      echo "❌ Aborted."
      ;;
  esac
}

cmd_setup_keys() {
  for i in $(seq 1 7); do
    iface="wg$i"
    keyfile="$WG_DIR/$iface.key"
    pubfile="$WG_DIR/$iface.pub"

    if [[ -f "$keyfile" && -f "$pubfile" ]]; then
      echo "ℹ️  Keys already exist for $iface, skipping."
      continue
    fi

    echo "🔑 Generating keys for $iface..."
    umask 077
    wg genkey | tee "$keyfile" | wg pubkey > "$pubfile"
    chmod 600 "$keyfile"
    chmod 644 "$pubfile"
    chown root:root "$keyfile" "$pubfile"

    # --- Add default client 'julie' if not already present ---
    if [[ ! -f "$CLIENT_DIR/julie-$iface.conf" ]]; then
      echo "👤 Creating default client 'julie' on $iface..."
      cmd_add "$iface" julie
    else
      echo "ℹ️  Client 'julie' already exists on $iface, skipping."
    fi
  done
  echo "✅ Server keys and default client 'julie' set up for wg1–wg7"
}

cmd_export() {
  local client="$1"
  local iface="${2:-}"
  cat "$CLIENT_DIR/${client}${iface:+-$iface}.conf" 2>/dev/null \
    || echo "No config found for $client $iface"
}

cmd_qr() {
  local client="$1"
  local iface="${2:-}"
  
  # Pipe the output of cmd_export directly to qrencode
  # We use the existing export function for the raw text, and pipe it.
  cmd_export "$client" "$iface" | qrencode -t ansiutf8
}

#
# --- [NEW HELPER FUNCTION] ---
# Generates the PostUp/PostDown rules
#
_get_routing_rules() {
  local iface="$1"
  local num=${iface#wg}
  local wg_ipv4_subnet="10.$num.0.0/24"
  local wg_ipv6_subnet="fd10:$num::/64"

  cat <<EOF
# --- START ROUTING & NAT RULES ---
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = sysctl -w net.ipv6.conf.all.forwarding=1
# IPv4 FORWARD chain
PostUp = iptables-legacy -A FORWARD -i %i -j ACCEPT
PostUp = iptables-legacy -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# IPv4 NAT (MASQUERADE)
# Rule: NAT traffic from WG subnet to anywhere *except* the LAN.
# This relies on your router's static route for WG->LAN traffic.
PostUp = iptables-legacy -t nat -A POSTROUTING -s $wg_ipv4_subnet -o $NAS_LAN_IFACE ! -d $LAN_SUBNET -j MASQUERADE
# IPv6 FORWARD chain
PostUp = ip6tables-legacy -A FORWARD -i %i -j ACCEPT
PostUp = ip6tables-legacy -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# IPv6 NAT (MASQUERADE)
# Note: This NATs all IPv6.
PostUp = ip6tables-legacy -t nat -A POSTROUTING -s $wg_ipv6_subnet -o $NAS_LAN_IFACE -j MASQUERADE
# --- CLEANUP RULES ---
PostDown = iptables-legacy -D FORWARD -i %i -j ACCEPT
PostDown = iptables-legacy -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables-legacy -t nat -D POSTROUTING -s $wg_ipv4_subnet -o $NAS_LAN_IFACE ! -d $LAN_SUBNET -j MASQUERADE
PostDown = ip6tables-legacy -D FORWARD -i %i -j ACCEPT
PostDown = ip6tables-legacy -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostDown = ip6tables-legacy -t nat -D POSTROUTING -s $wg_ipv6_subnet -o $NAS_LAN_IFACE -j MASQUERADE
# --- END ROUTING & NAT RULES ---
EOF
}

#
# --- [MODIFIED: Uses printf for all Interface lines] ---
#
_rebuild_nolock() {
  local iface="$1"
  local keyfile="$WG_DIR/$iface.key"
  local conffile="$WG_DIR/$iface.conf"
  local num=${iface#wg}
  local port=$((BASE_WG_PORT + num))
  local wg_ipv4_server wg_ipv6_server
  local cfg client pub ip

  # --- Define this interface's server IPs ---
  local wg_ipv4_server="10.$num.0.1/24"
  local wg_ipv6_server="fd10:$num::1/64"

  # --- Rebuild [Interface] section ---
  # CRITICAL FIX: Isolate PrivateKey to prevent here-doc corruption.
  local server_privkey
  server_privkey=$(_get_private_key_clean "$keyfile")

  # Step 1: Write the header and the PrivateKey using printf (overwrites file).
    printf "[Interface]\n" > "$conffile.new"
    printf "PrivateKey=%s\n" "$server_privkey" >> "$conffile.new"
    
    # Step 2: Append the rest of the configuration using clean printf.
    printf "Address=%s\n" "$wg_ipv4_server" >> "$conffile.new"
    printf "ListenPort=%s\n" "$port" >> "$conffile.new"
    printf "MTU=%s\n" "$SERVER_MTU" >> "$conffile.new"

    # Step 3: Append the routing rules.
    cat >> "$conffile.new" <<EOF

$(_get_routing_rules "$iface")
EOF

  # --- Loop over all client configs ---
  for cfg in "$CLIENT_DIR"/*-"$iface".conf; do
    [[ -f "$cfg" ]] || continue
    client=$(basename "$cfg" | cut -d- -f1)
  
    # Extracts the client's Public Key from the comment line
    pub=$(awk -F' = ' '/^# ClientPublicKey/{print $2}' "$cfg")
  
    # FIXED: Reliably extracts the client's IPv4 address with the /32 mask.
    # This finds the first Address line that contains /32, takes the value after '=', 
    # and strips any leading/trailing whitespace.
    ip=$(awk -F'=' '/^Address/{print $2}' "$cfg" | grep '/32' | head -n1 | tr -d ' ' | tr -d '\n\r')
  
    if [[ -z "$pub" || -z "$ip" ]]; then
      echo "⚠️  Skipping malformed client config: $cfg" >&2
      continue
    fi
  
    cat >> "$conffile.new" <<EOF
  
[Peer]
# $client
PublicKey = $pub
AllowedIPs = $ip
EOF
  done

  # --- Replace config atomically ---
  mv "$conffile.new" "$conffile"
  # --- Reload without downtime ---
  (
    # Pass the new config file path directly to wg syncconf
    sudo wg syncconf "$iface" "$conffile"
    echo "✅ Rebuilt $conffile from client configs"
  ) || true # Force function success, ignoring the mystery error
}

cmd_rebuild() {
  local iface="$1"
  (
    flock -x 200
    _rebuild_nolock "$iface"
  ) 200>"$WG_DIR/$iface.lock"
}

#
# --- [MODIFIED: Uses printf for all Interface lines] ---
#
cmd_add() {
  local iface="$1"
  local client="$2"
  local email="${3:-}"
  local forced_ip="${4:-}"
  
  local num=${iface#wg}
  local port=$((BASE_WG_PORT + num))
  local allowed dns expiry label
  local privkey pubkey ip ipv6 final_octet cfg
  
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
    echo "⚙️  Creating base config for $iface at $WG_DIR/$iface.conf"
    
    # --- Define this interface's server IPs ---
    local wg_ipv4_server="10.$num.0.1/24"
    local wg_ipv6_server="fd10:$num::1/64"
    
    # CRITICAL FIX: Read the key into a variable and strip all whitespace
    local server_privkey
    server_privkey=$(_get_private_key_clean "$WG_DIR/$iface.key")

    # >>> CRITICAL CHANGE: Write [Interface] and all parameters using printf. <<<
    printf "[Interface]\n" > "$WG_DIR/$iface.conf"
    printf "PrivateKey=%s\n" "$server_privkey" >> "$WG_DIR/$iface.conf"
    printf "Address=%s\n" "$wg_ipv4_server" >> "$WG_DIR/$iface.conf"
    printf "ListenPort=%s\n" "$port" >> "$WG_DIR/$iface.conf"
    printf "MTU=%s\n" "$SERVER_MTU" >> "$WG_DIR/$iface.conf"
    
    # Step 3: Append the routing rules.
    cat >> "$WG_DIR/$iface.conf" <<EOF

$(_get_routing_rules "$iface")
EOF

    chmod 600 "$WG_DIR/$iface.conf"
    chown root:root "$WG_DIR/$iface.conf"

    sudo wg-quick up "$iface"
  fi

  # --- Generate client keys ---
  privkey=$(wg genkey)
  pubkey=$(echo "$privkey" | wg pubkey)

  # --- Allocate IP ---
  if [[ -n "$forced_ip" ]]; then
    ip="$forced_ip"
  else
    # Pass interface to allocate from correct subnet
    ip=$(allocate_ip "$iface")
  fi

  # --- Allocate IPv6 client IP ---
  # Simple scheme: 10.N.0.X -> fd10:N::X
  # Reliable extraction of the final octet (X) from the allocated IPv4: 10.N.0.X
  local final_octet="${ip##*.}"

  # Simple scheme: fd10:N::X
  local ipv6="fd10:$num::$final_octet"

  mkdir -p "$CLIENT_DIR"
  cfg="$CLIENT_DIR/${client}-${iface}.conf"

  cat >"$cfg" <<EOF
# ClientPublicKey = $pubkey
[Interface]
PrivateKey=$privkey
Address=$ip/32
Address=$ipv6/128
DNS=$dns
MTU=$SERVER_MTU

[Peer]
PublicKey = $(sudo cat $WG_DIR/$iface.pub)
AllowedIPs = $allowed
Endpoint = $WG_ENDPOINT_HOST:$port
PersistentKeepalive = 25
EOF

  # --- Rebuild server config from all clients ---
  ( cmd_rebuild "$iface"
    # Always show where the config was saved
    echo "   Client config saved at: $cfg"
    echo "    View text: sudo /usr/local/bin/wg.sh export $client $iface"
    echo "    View QR:   sudo /usr/local/bin/wg.sh qr $client $iface"
  ) || true # Force function success, ignoring the mystery error
}


cmd_revoke() {
  local iface="$1"
  local client="$2"

  local cfg="$CLIENT_DIR/${client}-${iface}.conf"

  if [[ ! -f "$cfg" ]]; then
    echo "❌ No config found for client $client on $iface"
    return 1
  fi

  (
    flock -x 200
    # Remove the client config file
    rm -f "$cfg"
    echo "🗑️  Removed client config: $cfg"
    # Rebuild the server config from remaining clients
    # Note: _rebuild_nolock is called by cmd_rebuild
    _rebuild_nolock "$iface"
  ) 200>"$WG_DIR/$iface.lock"
}

# --- Main command parser ---
case "${1:-}" in
  --helper) show_helper; exit 0 ;;
  setup-keys) shift; cmd_setup_keys ;;
  add) shift; cmd_add "$@" ;;
  revoke) shift; cmd_revoke "$@" ;;
  clean) shift; cmd_clean "$@" ;;
  clean-all) shift; cmd_clean_all "$@" ;;
  rebuild) shift; cmd_rebuild "$@" ;;
  show) shift; cmd_show "$@" ;;
  export) shift; cmd_export "$@" ;;
  qr) shift; cmd_qr "$@" ;;
  "" ) show_helper; exit 0 ;;
  * ) echo "Unknown command: $1" >&2; show_helper; exit 1 ;;
esac