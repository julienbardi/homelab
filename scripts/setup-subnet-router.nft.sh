#!/bin/bash
# setup-subnet-router.nft.sh
# Idempotent nft conversion of setup-subnet-router.sh
set -euo pipefail

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

# --- Topology (adjust if needed) ---
LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
WG_IF_PREFIX="wg"
VPN_SUBNET_PREFIX="10"   # wgN -> 10.N.0.0/24
GLOBAL_IPV6_PREFIX="2a01:8b81:4800:9c00"
GLOBAL_PREFIX_LEN=64

# --- Require root ---
if [[ $EUID -ne 0 ]]; then
  log "ERROR: must run as root"
  exit 1
fi

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
  log "ERROR: Interface ${LAN_IF} not found or not UP, aborting."
  exit 1
fi

# --- Kernel tuning: IPv4/IPv6 forwarding ---
log "Enabling IPv4/IPv6 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
sysctl -w net.ipv6.conf.default.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf.default.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf."${LAN_IF}".forwarding=1 >/dev/null || true

# --- Ensure nft tables/chains exist (idempotent) ---
log "Ensuring nft base tables and chains..."
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
  chain forward { type filter hook forward priority 0; policy drop; }
}
EOF

# --- Helper to add rule if missing ---
add_rule() {
  local check="$1"; shift
  local cmd="$*"
  if ! nft -a list ruleset | grep -F -q "$check"; then
	log "Adding rule: $check"
	eval "$cmd"
  else
	log "Already present: $check"
  fi
}

# --- Conntrack baseline (ESTABLISHED,RELATED) ---
add_rule "ct state related,established accept" \
  "nft add rule inet filter input ct state related,established accept"
add_rule "ct state related,established accept FORWARD" \
  "nft add rule inet filter forward ct state related,established accept"

# --- LAN host accepts (IPv4 + IPv6) ---
add_rule "iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept" \
  "nft add rule ip filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept"
add_rule "iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept" \
  "nft add rule ip6 filter input iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept"

# --- Essential service ports on host (DNS/SSH/HTTPS/UPnP/SMB/wsdd2) ---
add_rule "tcp dport 443 accept" \
  "nft add rule inet filter input tcp dport 443 accept"
add_rule "udp dport 53 accept" \
  "nft add rule ip filter input udp dport 53 accept"
add_rule "tcp dport 53 accept" \
  "nft add rule ip filter input tcp dport 53 accept"
add_rule "tcp dport 22 accept" \
  "nft add rule ip filter input tcp dport 22 accept"
add_rule "tcp dport 2222 accept" \
  "nft add rule ip filter input tcp dport 2222 accept"
add_rule "tcp dport 9999 accept" \
  "nft add rule ip filter input tcp dport 9999 accept"
add_rule "tcp dport 9443 accept" \
  "nft add rule ip filter input tcp dport 9443 accept"

# --- WireGuard handshake ports on LAN uplink (bridge0) ---
# Accept UDP 51421-51427 on LAN_IF for both IPv4 and IPv6
add_rule "iifname \"${LAN_IF}\" udp dport 51421-51427 accept" \
  "nft add rule ip filter input iifname \"${LAN_IF}\" udp dport {51421-51427} ct state new,established accept"
add_rule "iifname \"${LAN_IF}\" udp dport 51421-51427 accept ip6" \
  "nft add rule ip6 filter input iifname \"${LAN_IF}\" udp dport {51421-51427} ct state new,established accept"

# --- WireGuard per-interface host + forward rules (wg0..wg7) ---
for i in $(seq 0 7); do
  WG_IF="${WG_IF_PREFIX}${i}"
  IPV4_SUBNET="10.${i}.0.0/24"
  IPV6_SUBNET="${GLOBAL_IPV6_PREFIX}:1${i}::/64"
  PORT=$((51420 + i))

  if ip link show "${WG_IF}" >/dev/null 2>&1; then
	log "Configuring ${WG_IF} rules (subnets ${IPV4_SUBNET}, ${IPV6_SUBNET}, port ${PORT})"

	add_rule "iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept" \
	  "nft add rule ip filter input iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept"
	add_rule "iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} forward-accept" \
	  "nft add rule ip filter forward iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept"
	add_rule "oifname \"${WG_IF}\" ip daddr ${IPV4_SUBNET} forward-accept" \
	  "nft add rule ip filter forward oifname \"${WG_IF}\" ip daddr ${IPV4_SUBNET} accept"

	add_rule "iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept" \
	  "nft add rule ip6 filter input iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept"
	add_rule "iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} forward-accept" \
	  "nft add rule ip6 filter forward iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept"
	add_rule "oifname \"${WG_IF}\" ip6 daddr ${IPV6_SUBNET} forward-accept" \
	  "nft add rule ip6 filter forward oifname \"${WG_IF}\" ip6 daddr ${IPV6_SUBNET} accept"

	# Handshake path on LAN uplink: accept UDP port for this interface (no source restriction)
	add_rule "iifname \"${LAN_IF}\" udp dport ${PORT} accept" \
	  "nft add rule ip filter input iifname \"${LAN_IF}\" udp dport ${PORT} ct state new,established accept"
	add_rule "iifname \"${LAN_IF}\" udp dport ${PORT} accept ip6" \
	  "nft add rule ip6 filter input iifname \"${LAN_IF}\" udp dport ${PORT} ct state new,established accept"

	# Profile-based NAT for Internet egress (bitmask model)
	if [[ "${i}" =~ ^(2|3|6|7)$ ]]; then
	  add_rule "oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} masquerade" \
		"nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} masquerade"
	  # IPv6 forwarding already allowed above; no NAT66
	fi

	log "✅ ${WG_IF} nft rules ensured."
  else
	log "⚠️ ${WG_IF} not present, skipping."
  fi
done

# --- Tailscale rules (if present) ---
TS_IF="tailscale0"
TS_SUBNET_V4="100.64.0.0/10"
TS_SUBNET_V6="fd7a:115c:a1e0::/48"

if ip link show "${TS_IF}" >/dev/null 2>&1; then
  add_rule "iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept" \
	"nft add rule ip filter input iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
  add_rule "iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} forward-accept" \
	"nft add rule ip filter forward iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
  add_rule "oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} forward-accept" \
	"nft add rule ip filter forward oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} accept"
  add_rule "oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade" \
	"nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade"

  add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept" \
	"nft add rule ip6 filter input iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
  add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} forward-accept" \
	"nft add rule ip6 filter forward iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
  add_rule "oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} forward-accept" \
	"nft add rule ip6 filter forward oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} accept"

  log "Tailscale nft rules applied."
else
  log "Tailscale interface ${TS_IF} not found, skipping Tailscale rules."
fi

# --- GRO tuning ---
log "Applying GRO tuning on ${LAN_IF}..."
if ethtool -K "${LAN_IF}" gro off 2>/dev/null; then
  log "GRO disabled on ${LAN_IF}"
else
  log "WARN: Failed to disable GRO on ${LAN_IF}"
fi

# --- Configure NDP proxying (ndppd preferred) ---
log "Configuring NDP proxying for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN}..."
if command -v ndppd >/dev/null 2>&1; then
  log "ndppd found; writing configuration and restarting service..."
  cat > /etc/ndppd.conf <<EOF
route-ttl 300
proxy ${LAN_IF} {
  router yes
  timeout 500
  ttl 300
  rule ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} {
	auto
  }
}
EOF
  systemctl daemon-reload || true
  systemctl enable --now ndppd.service || true
  systemctl restart ndppd.service || true
  log "ndppd configured."
else
  log "ndppd not installed; attempting apt install..."
  if apt-get update && apt-get install -y ndppd; then
	log "ndppd installed and configured."
	systemctl enable --now ndppd.service || true
  else
	log "WARN: ndppd install failed; adding conservative ip -6 neigh proxy entries for expected clients."
	CLIENT_ADDRS=(
	  "${GLOBAL_IPV6_PREFIX}:10::2"
	  "${GLOBAL_IPV6_PREFIX}:11::2"
	  "${GLOBAL_IPV6_PREFIX}:12::2"
	  "${GLOBAL_IPV6_PREFIX}:13::2"
	)
	for addr in "${CLIENT_ADDRS[@]}"; do
	  if ! ip -6 neigh show proxy | grep -q "${addr}"; then
		ip -6 neigh add proxy "${addr}" dev "${LAN_IF}" || true
		log "Added proxy NDP for ${addr}"
	  else
		log "Proxy NDP already present for ${addr}"
	  fi
	done
  fi
fi

# Ensure kernel route for the /64 is present (idempotent)
ip -6 route replace ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} dev "${WG_IF_PREFIX}0" >/dev/null 2>&1 || true
log "Local route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} ensured."

# --- Persist nft ruleset and enable nftables service ---
log "Persisting nft ruleset to /etc/nftables.conf..."
nft list ruleset > /etc/nftables.conf
systemctl enable --now nftables || true
log "Subnet router nft configuration complete."
