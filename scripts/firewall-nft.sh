#!/bin/bash
# firewall-nft.sh
# Minimal idempotent nft-based firewall for NAS host
set -euo pipefail

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

# --- Variables (adjust as needed) ---
LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
WG_IF="wg0"
WG_PORT=51822
WG_SUBNET="10.4.0.0/24"
TAILSCALE_IF="tailscale0"
TAILSCALE_SUBNET="100.64.0.0/10"

if [[ $EUID -ne 0 ]]; then
  log "ERROR: must run as root"
  exit 1
fi

# Ensure base tables/chains exist
nft -f - <<'EOF' || true
table inet filter {
  chain input { type filter hook input priority 0; policy drop; }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output { type filter hook output priority 0; policy accept; }
}
table ip nat {
  chain postrouting { type nat hook postrouting priority 100; policy accept; }
}
table ip6 filter {
  chain input { type filter hook input priority 0; policy accept; }
}
EOF

# Helper to add rule if missing
add_rule() {
  local check="$1"; shift
  local cmd="$*"
  if ! nft -a list ruleset | grep -F -q "$check"; then
	log "Adding: $check"
	eval "$cmd"
  else
	log "Already present: $check"
  fi
}

# Conntrack baseline
add_rule "ct state related,established accept" \
  "nft add rule inet filter input ct state related,established accept"
add_rule "ct state related,established accept FORWARD" \
  "nft add rule inet filter forward ct state related,established accept"

# Allow loopback
add_rule "iifname \"lo\" accept" \
  "nft add rule inet filter input iifname \"lo\" accept"

# Allow LAN subnet full access to host services (scoped)
add_rule "iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept"
add_rule "iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept"

# Allow SSH (22,2222) from LAN
add_rule "tcp dport 22 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} tcp dport 22 accept"
add_rule "tcp dport 2222 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} tcp dport 2222 accept"

# Allow NAS Web UI from LAN (9999,9443)
add_rule "tcp dport 9999 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} tcp dport 9999 accept"
add_rule "tcp dport 9443 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} tcp dport 9443 accept"

# Allow DNS from LAN and WG/Tailscale subnets
add_rule "udp dport 53 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
  "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} udp dport 53 accept"
add_rule "udp dport 53 ip saddr ${WG_SUBNET}" \
  "nft add rule inet filter input ip saddr ${WG_SUBNET} udp dport 53 accept"
add_rule "udp dport 53 ip saddr ${TAILSCALE_SUBNET}" \
  "nft add rule inet filter input ip saddr ${TAILSCALE_SUBNET} udp dport 53 accept"

# Allow incoming WireGuard handshake (UDP)
add_rule "udp dport ${WG_PORT} accept" \
  "nft add rule inet filter input udp dport ${WG_PORT} ct state new,established accept"
add_rule "udp dport ${WG_PORT} accept ip6" \
  "nft add rule inet filter input udp dport ${WG_PORT} ct state new,established accept"

# Tailscale interface full accept (if present)
if ip link show "${TAILSCALE_IF}" >/dev/null 2>&1; then
  add_rule "iifname \"${TAILSCALE_IF}\" accept" \
	"nft add rule inet filter input iifname \"${TAILSCALE_IF}\" accept"
fi

# NAT for WireGuard subnet egress (example)
add_rule "oifname != \"docker0\" ip saddr ${WG_SUBNET} masquerade" \
  "nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${WG_SUBNET} masquerade"

# Persist ruleset
nft list ruleset > /etc/nftables.conf
systemctl enable --now nftables || true

log "firewall-nft: rules ensured and persisted"
