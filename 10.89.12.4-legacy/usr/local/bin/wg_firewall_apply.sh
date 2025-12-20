#!/usr/bin/env bash
# wg_firewall_apply.sh
# Idempotent firewall deployment for WG interfaces wg0..wg7 on UGOS NAS
# Usage: sudo /usr/local/bin/wg_firewall_apply.sh [apply|remove|status]
# - apply:      apply desired ruleset (create/ensure)
# - remove:     remove all rules this script manages
# - status:     show summary of active rules the script manages
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/wg_firewall_apply.sh /usr/local/bin/

set -euo pipefail

# -------------------------
# Configuration (edit only here)
# -------------------------
NAS_LAN_IFACE="bridge0"
LAN_SUBNET="10.89.12.0/24"
NAS_IP4="10.89.12.4"
NAS_IP6="2a01:8b81:4800:9c00::1"   # NAS uses ::1 per your notes
WG_IFACES=(wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7)
# Map of wgN -> UDP port (must match your router forwarding)
declare -A WG_PORTS=(
  [wg0]=51820 [wg1]=51821 [wg2]=51822 [wg3]=51823
  [wg4]=51824 [wg5]=51825 [wg6]=51826 [wg7]=51827
)
# Shared global IPv6 prefix and infra reserved range
GLOBAL_IPV6_PREFIX="2a01:8b81:4800:9c00::/64"
INFRA_IPV6_RANGE="::2-::ff"
# Server/infra IPv4 reservations (.1 reserved for server)
# Clients allocate .100-.199 per subnet (10.X.0.100-199)
# AllowedIPs on peers must be specified in the WG config as IPv4/32 and IPv6/128

# Bitmask meanings (bit1=LAN, bit2=Internet, bit3=IPv6)
# Predefined per your mapping (index by interface number)
# Values 0..7
BITMASKS=(0 1 2 3 4 5 6 7)

# -------------------------
# Utilities: detect iptables binaries
# -------------------------
IPT=""
IP6T=""
IPT_TABLE_PREFIX=()  # helper where -t nat is needed for nat ops (some binaries require -t)
# Prefer iptables-legacy/ip6tables-legacy if present; otherwise use iptables/ip6tables
if command -v iptables-legacy >/dev/null 2>&1 && command -v ip6tables-legacy >/dev/null 2>&1; then
  IPT="iptables-legacy"
  IP6T="ip6tables-legacy"
else
  # fallback to system iptables, ip6tables (may be nft wrapper)
  IPT="iptables"
  IP6T="ip6tables"
fi

# Small helper to run iptables with nat table option where needed
run_ipt() { $IPT "$@"; }
run_ip6t() { $IP6T "$@"; }

# -------------------------
# Safety and idempotency helpers
# -------------------------
MARKER_COMMENT="# managed-by-wg_firewall_apply"
rule_exists_ipt() {
  # args: full rule in -C style after chain (e.g., FORWARD -i wg1 -j ACCEPT)
  # returns 0 if rule exists
  set +e
  $IPT -C "$@" >/dev/null 2>&1
  rc=$?
  set -e
  return $rc
}
# Check whether an ip6tables rule exists safely (uses -C). Returns 0 if present, non‑zero otherwise.
rule_exists_ip6t() {
  set +e
  $IP6T -C "$@" >/dev/null 2>&1
  rc=$?
  set -e
  return $rc
}
# add rule only if not present
ensure_ipt_rule() {
  if ! rule_exists_ipt "$@"; then
    $IPT -I "$@" 2>/dev/null || $IPT -A "$@" # try insert, fallback to append
  fi
}
ensure_ip6t_rule() {
  if ! rule_exists_ip6t "$@"; then
    $IP6T -I "$@" 2>/dev/null || $IP6T -A "$@"
  fi
}
# nat table operations need -t nat
ensure_ipt_nat_rule() {
  # usage: ensure_ipt_nat_rule POSTROUTING <args...>
  chain="$1"; shift
  set +e
  $IPT -t nat -C "$chain" "$@" >/dev/null 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    $IPT -t nat -A "$chain" "$@"
  fi
}
ensure_ip6t_nat_rule() {
  chain="$1"; shift
  set +e
  $IP6T -t nat -C "$chain" "$@" >/dev/null 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    $IP6T -t nat -A "$chain" "$@"
  fi
}

# delete exact nat rule if present
delete_ipt_nat_rule() {
  chain="$1"; shift
  set +e
  $IPT -t nat -C "$chain" "$@" >/dev/null 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    $IPT -t nat -D "$chain" "$@"
  fi
}
delete_ip6t_nat_rule() {
  chain="$1"; shift
  set +e
  $IP6T -t nat -C "$chain" "$@" >/dev/null 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    $IP6T -t nat -D "$chain" "$@"
  fi
}

# -------------------------
# Low risk baseline rules (always ensure)
# -------------------------
ensure_baseline() {
  # Enable forwarding in sysctl for runtime
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

  # Allow established/related for IPv4 and IPv6 (filter FORWARD)
  ensure_ipt_rule FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ensure_ip6t_rule FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # Permit traffic on loopback and from NAS itself (do not lock out local services)
  ensure_ipt_rule INPUT -i lo -j ACCEPT
  ensure_ip6t_rule INPUT -i lo -j ACCEPT

  # Allow management/SSH from LAN to NAS (safe guard: keep SSH open from LAN)
  # You can modify these networks if your admin subnet differs
  # Allow management/SSH from LAN to NAS (keep SSH open from LAN)
  ensure_ipt_rule INPUT -i "${NAS_LAN_IFACE}" -s "${LAN_SUBNET}" -p tcp --dport 22 -j ACCEPT
  ensure_ipt_rule INPUT -i "${NAS_LAN_IFACE}" -s "${LAN_SUBNET}" -p tcp --dport 2222 -j ACCEPT

  ensure_ipt_rule INPUT -i "${NAS_LAN_IFACE}" -s "${LAN_SUBNET}" -j ACCEPT
  ensure_ip6t_rule INPUT -i "${NAS_LAN_IFACE}" -s "${GLOBAL_IPV6_PREFIX}" -p tcp --dport 22 -j ACCEPT || true
  ensure_ip6t_rule INPUT -i "${NAS_LAN_IFACE}" -s "${GLOBAL_IPV6_PREFIX}" -p tcp --dport 2222 -j ACCEPT || true
  
  # Allow the NAS to talk outbound (so it continues to resolve / use internet)
  ensure_ipt_rule OUTPUT -o "$NAS_LAN_IFACE" -j ACCEPT || true
  ensure_ip6t_rule OUTPUT -o "$NAS_LAN_IFACE" -j ACCEPT || true
}

# -------------------------
# Per-interface rules application
# -------------------------
apply_wg_iface() {
  local iface="$1"
  # Extract numeric index
  local num=${iface#wg}
  # IPv4/IPv6 subnets per your addressing plan
  local ipv4_subnet="10.${num}.0.0/24"
  # IPv4 client range (not directly used by firewall unless you want to restrict)
  local ipv4_clients_range="10.${num}.0.100-10.${num}.0.199"

  # IPv6 per your "client allocation range" inside the shared /64
  # We treat each client as /128; for MASQUERADE use the per-interface ::/128 space
  # Build a pseudo-subnet for ip6tables nat POSTROUTING matching source prefix
  # We will use addresses ::${num}00/120 as a matching heuristic (non-standard, best-effort)
  # But we will also accept a simpler approach: NAT based on interface (-s <subnet> not always available for individual addresses)
  local ipv6_subnet="${GLOBAL_IPV6_PREFIX%%/64}::${num}00/120"  # heuristic string, not necessarily real

  # Determine bitmask (safely)
  local bitmask="${BITMASKS[$num]:-0}"

  # If bit2 (value 2) set -> Internet access for IPv4
  local want_ipv4_internet=$(( (bitmask & 2) != 0 ))
  # If bit1 (value 1) set -> LAN IPv4 access
  local want_ipv4_lan=$(( (bitmask & 1) != 0 ))
  # If bit3 (value 4) set -> IPv6 access
  local want_ipv6=$(( (bitmask & 4) != 0 ))

  # Always allow established connections for this interface
  ensure_ipt_rule FORWARD -i "$iface" -j ACCEPT
  ensure_ipt_rule FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ensure_ip6t_rule FORWARD -i "$iface" -j ACCEPT
  ensure_ip6t_rule FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # IPv4 NAT for internet access (masquerade outgoing via NAS_LAN_IFACE)
  if [ "$want_ipv4_internet" -eq 1 ]; then
    # NAT only for traffic that leaves to non-LAN destinations
    ensure_ipt_nat_rule POSTROUTING -s "$ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE
  else
    # ensure removal if exists
    delete_ipt_nat_rule POSTROUTING -s "$ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE || true
  fi

  # IPv4 LAN access: ensure forwarding to LAN (no NAT)
  if [ "$want_ipv4_lan" -eq 1 ]; then
    ensure_ipt_rule FORWARD -i "$iface" -o "$NAS_LAN_IFACE" -d "$LAN_SUBNET" -j ACCEPT
    ensure_ipt_rule FORWARD -i "$NAS_LAN_IFACE" -o "$iface" -s "$LAN_SUBNET" -j ACCEPT
  else
    # remove rules if present (best-effort delete using -C then -D)
    set +e
    $IPT -C FORWARD -i "$iface" -o "$NAS_LAN_IFACE" -d "$LAN_SUBNET" -j ACCEPT >/dev/null 2>&1 && $IPT -D FORWARD -i "$iface" -o "$NAS_LAN_IFACE" -d "$LAN_SUBNET" -j ACCEPT
    $IPT -C FORWARD -i "$NAS_LAN_IFACE" -o "$iface" -s "$LAN_SUBNET" -j ACCEPT >/dev/null 2>&1 && $IPT -D FORWARD -i "$NAS_LAN_IFACE" -o "$iface" -s "$LAN_SUBNET" -j ACCEPT
    set -e
  fi

  # IPv6 rules and NAT (where supported). Note: IPv6 NAT is non-standard; many systems provide ip6tables -t nat MASQUERADE via kernel modules.
  if [ "$want_ipv6" -eq 1 ]; then
    # Allow forwarding of IPv6 from/to iface
    ensure_ip6t_rule FORWARD -i "$iface" -o "$NAS_LAN_IFACE" -j ACCEPT
    ensure_ip6t_rule FORWARD -i "$NAS_LAN_IFACE" -o "$iface" -j ACCEPT
    # Attempt IPv6 POSTROUTING MASQUERADE if nat table exists
    set +e
    if $IP6T -t nat -L >/dev/null 2>&1; then
      set -e
      # Use -s with the real source prefix if you assign clients inside a proper delegated prefix.
      # For safety we match interface-based traffic only (masquerade outgoing from interface)
      ensure_ip6t -t nat >/dev/null 2>&1 || true
      # Because interface-based ip6tables nat matching is not uniform, best-effort:
      ensure_ip6t_nat_rule POSTROUTING -s "${GLOBAL_IPV6_PREFIX}" -o "$NAS_LAN_IFACE" -j MASQUERADE || true
    else
      set -e
      # nat table absent: rely on routing (preferred for IPv6). No NAT action.
      :
    fi
  else
    # If IPv6 not allowed, explicitly DROP forwarding from this iface to ::/0
    # But ensure we do not drop established connections
    # Add a rule that drops new/invalid forwarded IPv6 from iface to outside
    set +e
    $IP6T -C FORWARD -i "$iface" -m conntrack --ctstate NEW -j DROP >/dev/null 2>&1 || $IP6T -A FORWARD -i "$iface" -m conntrack --ctstate NEW -j DROP
    set -e
  fi
}

# -------------------------
# Manage all interfaces
# -------------------------
apply_all() {
  echo "Applying baseline rules..."
  ensure_baseline

  # Check nppd service presence (best-effort check)
  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet nppd; then
      echo "Warning: nppd not active. IPv6 prefix delegation services may be unavailable."
    fi
  fi

  # Apply per-WG interface rules
  for iface in "${WG_IFACES[@]}"; do
    echo "Applying rules for $iface..."
    apply_wg_iface "$iface"
  done

  # Ensure external reachability for WireGuard UDP ports on NAS itself (INPUT accept to WG ports)
  for iface in "${WG_IFACES[@]}"; do
    port=${WG_PORTS[$iface]}
    # Accept UDP to NAS on these ports (incoming from WAN). Interface check not used; user router forwards to NAS IP.
    ensure_ipt_rule INPUT -p udp --dport "$port" -d "$NAS_IP4" -j ACCEPT
    # IPv6 acceptance for WireGuard endpoint if NAS has global IPv6
    ensure_ip6t_rule INPUT -p udp --dport "$port" -d "$NAS_IP6" -j ACCEPT || true
  done

  echo "Done. To avoid duplicates you may run the remove-dup-rule helper for chains POSTROUTING/FORWARD as needed."
}

# -------------------------
# Removal (undo what we added)
# -------------------------
remove_all() {
  echo "Removing rules managed by this script (best-effort)..."

  # Remove WG-related NAT rules for IPv4
  for num in $(seq 0 7); do
    ipv4_subnet="10.${num}.0.0/24"
    set +e
    $IPT -t nat -C POSTROUTING -s "$ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE >/dev/null 2>&1 && $IPT -t nat -D POSTROUTING -s "$ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE
    set -e
  done

  # Remove generic interface rules created above (best-effort deletions)
  for iface in "${WG_IFACES[@]}"; do
    set +e
    $IPT -C FORWARD -i "$iface" -j ACCEPT >/dev/null 2>&1 && $IPT -D FORWARD -i "$iface" -j ACCEPT
    $IPT -C FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1 && $IPT -D FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    $IP6T -C FORWARD -i "$iface" -j ACCEPT >/dev/null 2>&1 && $IP6T -D FORWARD -i "$iface" -j ACCEPT
    $IP6T -C FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1 && $IP6T -D FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    set -e
  done

  # Remove WireGuard input UDP allow rules
  for iface in "${WG_IFACES[@]}"; do
    port=${WG_PORTS[$iface]}
    set +e
    $IPT -C INPUT -p udp --dport "$port" -d "$NAS_IP4" -j ACCEPT >/dev/null 2>&1 && $IPT -D INPUT -p udp --dport "$port" -d "$NAS_IP4" -j ACCEPT
    $IP6T -C INPUT -p udp --dport "$port" -d "$NAS_IP6" -j ACCEPT >/dev/null 2>&1 && $IP6T -D INPUT -p udp --dport "$port" -d "$NAS_IP6" -j ACCEPT
    set -e
  done

  echo "Removal complete (best-effort)."
}

# -------------------------
# Status print
# -------------------------
status_print() {
  echo "Using IPv4 tool: $IPT"
  echo "Using IPv6 tool: $IP6T"
  echo
  echo "Filter FORWARD rules (IPv4):"
  $IPT -L FORWARD --line-numbers -n || true
  echo
  echo "NAT POSTROUTING (IPv4):"
  $IPT -t nat -L POSTROUTING --line-numbers -n || true
  echo
  echo "Filter FORWARD rules (IPv6):"
  $IP6T -L FORWARD --line-numbers -n || true
  echo
  echo "NAT POSTROUTING (IPv6) if available:"
  set +e
  $IP6T -t nat -L POSTROUTING --line-numbers -n 2>/dev/null || echo "  (ip6tables nat table not available)"
  set -e
}

# -------------------------
# Entrypoint
# -------------------------
cmd="${1-apply}"

case "$cmd" in
  apply)
    apply_all
    ;;
  remove)
    remove_all
    ;;
  status)
    status_print
    ;;
  *)
    echo "Usage: $0 [apply|remove|status]" >&2
    exit 2
    ;;
esac