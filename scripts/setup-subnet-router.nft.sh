#!/bin/bash
# setup-subnet-router.nft.sh
# Idempotent nft conversion of setup-subnet-router.sh
set -euo pipefail

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

# --- Topology (adjust if needed) ---
LAN_IF="eth0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
WG_IF_PREFIX="wg"
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

# --- Ensure inet filter table/chains exist (vendor-safe) ---
log "Ensuring inet filter table and base chains..."
if ! nft list table inet filter >/dev/null 2>&1; then
	nft create table inet filter
fi

# Create chains only if missing; do NOT touch vendor ip/ip6 filter tables
nft create chain inet filter input   '{ type filter hook input priority 0; policy drop; }'   2>/dev/null || true
nft create chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' 2>/dev/null || true
nft create chain inet filter output  '{ type filter hook output priority 0; policy accept; }' 2>/dev/null || true

# Ensure ip nat table/chain exist (without touching vendor rules)
if ! nft list table ip nat >/dev/null 2>&1; then
	nft create table ip nat
fi
nft create chain ip nat postrouting '{ type nat hook postrouting priority 100; policy accept; }' 2>/dev/null || true

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
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept"
add_rule "iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept"

# --- Essential service ports on host (DNS/SSH/HTTPS/UPnP/SMB/wsdd2/etc.) ---
add_rule "tcp dport 443 accept" \
	"nft add rule inet filter input tcp dport 443 accept"
add_rule "udp dport 53 accept" \
	"nft add rule inet filter input udp dport 53 accept"
add_rule "tcp dport 53 accept" \
	"nft add rule inet filter input tcp dport 53 accept"
add_rule "tcp dport 22 accept" \
	"nft add rule inet filter input tcp dport 22 accept"
add_rule "tcp dport 2222 accept" \
	"nft add rule inet filter input tcp dport 2222 accept"
add_rule "tcp dport 9999 accept" \
	"nft add rule inet filter input tcp dport 9999 accept"
add_rule "tcp dport 9443 accept" \
	"nft add rule inet filter input tcp dport 9443 accept"

# SMB
add_rule "tcp dport 445 accept" \
	"nft add rule inet filter input tcp dport 445 accept"

# wsdd2
add_rule "udp dport 3702 accept" \
	"nft add rule inet filter input udp dport 3702 accept"

# UPnP/SSDP
add_rule "udp dport 1900 accept" \
	"nft add rule inet filter input udp dport 1900 accept"

# --- WireGuard handshake ports on LAN uplink ---
# Accept UDP 51420-51427 on LAN_IF (IPv4 + IPv6 via inet table)
add_rule "iifname \"${LAN_IF}\" udp dport 51420-51427 accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" udp dport {51420-51427} ct state new,established accept"

# --- WireGuard per-interface host + forward rules (wg0..wg7) ---
for i in $(seq 0 7); do
	WG_IF="${WG_IF_PREFIX}${i}"
	IPV4_SUBNET="10.${i}.0.0/24"
	IPV6_SUBNET="${GLOBAL_IPV6_PREFIX}:1${i}::/64"
	PORT=$((51420 + i))

	if ip link show "${WG_IF}" >/dev/null 2>&1; then
		log "Configuring ${WG_IF} rules (subnets ${IPV4_SUBNET}, ${IPV6_SUBNET}, port ${PORT})"

		# Host access from wgX
		add_rule "iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept" \
			"nft add rule inet filter input iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept"
		add_rule "iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept" \
			"nft add rule inet filter input iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept"

		# Forwarding wgX ↔ LAN / other networks
		add_rule "iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} forward-accept" \
			"nft add rule inet filter forward iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept"
		add_rule "oifname \"${WG_IF}\" ip daddr ${IPV4_SUBNET} forward-accept" \
			"nft add rule inet filter forward oifname \"${WG_IF}\" ip daddr ${IPV4_SUBNET} accept"

		add_rule "iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} forward-accept" \
			"nft add rule inet filter forward iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept"
		add_rule "oifname \"${WG_IF}\" ip6 daddr ${IPV6_SUBNET} forward-accept" \
			"nft add rule inet filter forward oifname \"${WG_IF}\" ip6 daddr ${IPV6_SUBNET} accept"

		# Handshake path on LAN uplink: accept UDP port for this interface (no source restriction)
		add_rule "iifname \"${LAN_IF}\" udp dport ${PORT} accept" \
			"nft add rule inet filter input iifname \"${LAN_IF}\" udp dport ${PORT} ct state new,established accept"

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
		"nft add rule inet filter input iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
	add_rule "iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} forward-accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
	add_rule "oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} forward-accept" \
		"nft add rule inet filter forward oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} accept"
	add_rule "oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade" \
		"nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade"

	add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept" \
		"nft add rule inet filter input iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
	add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} forward-accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
	add_rule "oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} forward-accept" \
		"nft add rule inet filter forward oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} accept"

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

# --- Configure NDP proxying (ndppd required, no auto-install) ---
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
	log "ERROR: ndppd is not installed. IPv6 routing for WireGuard/Tailscale clients will FAIL."
	log "ERROR: Install ndppd via 'make deps' (install-pkg-ndppd) and re-run this script."
	exit 1
fi

# Ensure kernel route for the /64 is present (idempotent)
log "Ensuring kernel route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} on ${LAN_IF}"
ip -6 route replace "${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN}" dev "${LAN_IF}" >/dev/null 2>&1 || true
log "Local route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} ensured."

# --- Persist nft ruleset (without touching vendor tables) ---
log "Persisting nft ruleset to /etc/nftables.conf..."
nft list ruleset > /etc/nftables.conf
log "Subnet router nft configuration complete."
