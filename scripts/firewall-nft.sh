#!/usr/bin/env bash
# firewall-nft.sh
# Idempotent nft-based firewall for NAS host aligned with mk/40_wireguard.mk
set -euo pipefail

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

# --- Variables (adjust only if your environment differs) ---
LAN_IF="eth0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
TAILSCALE_IF="tailscale0"
TAILSCALE_SUBNET="100.64.0.0/10"
TAILSCALE_SUBNET_V6="fd7a:115c:a1e0::/48"

# bitmask controlling which wg interfaces are active (bit0=wg0 .. bit7=wg7)
: "${WG_MASK:=0xff}"   # default enable all 8 if not set

# Per-interface IPv4 subnets (wg0..wg7) — matches mk/40_wireguard.mk
WG_SUBNETS=(
    "10.0.0.0/24"  # wg0
    "10.1.0.0/24"  # wg1
    "10.2.0.0/24"  # wg2
    "10.3.0.0/24"  # wg3
    "10.4.0.0/24"  # wg4
    "10.5.0.0/24"  # wg5
    "10.6.0.0/24"  # wg6
    "10.7.0.0/24"  # wg7
)

# Per-interface IPv6 /64s (server side) — matches mk/40_wireguard.mk
WG6_SUBNETS=(
    "2a01:8b81:4800:9c00:10::/64"  # wg0
    "2a01:8b81:4800:9c00:11::/64"  # wg1
    "2a01:8b81:4800:9c00:12::/64"  # wg2
    "2a01:8b81:4800:9c00:13::/64"  # wg3
    "2a01:8b81:4800:9c00:14::/64"  # wg4
    "2a01:8b81:4800:9c00:15::/64"  # wg5
    "2a01:8b81:4800:9c00:16::/64"  # wg6
    "2a01:8b81:4800:9c00:17::/64"  # wg7
)

# Per-interface WireGuard listen ports (wg0..wg7)
WG_PORTS=(51420 51421 51422 51423 51424 51425 51426 51427)

if [[ $EUID -ne 0 ]]; then
    log "ERROR: must run as root"
    exit 1
fi

UGOS=0
if nft list tables 2>/dev/null | grep -q '^table ip filter'; then
    UGOS=1
    log "Detected UGOS-managed firewall (iptables-nft compatibility mode)"
fi

# --- Enable kernel forwarding (runtime) ---
if sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
    log "IPv4 forwarding enabled"
else
    log "WARNING: failed to enable IPv4 forwarding"
fi

if sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1; then
    log "IPv6 forwarding enabled"
else
    log "WARNING: failed to enable IPv6 forwarding"
fi

# --- Ensure base tables/chains exist (idempotent) ---
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
    chain input { type filter hook input priority 0; policy drop; }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF

# Helper: add rule if missing (fast textual check + idempotent)
add_rule() {
    local check="$1"; shift
    local cmd="$*"
    if ! nft list chain inet filter input 2>/dev/null | grep -F -q "$check" \
       && ! nft list chain inet filter output 2>/dev/null | grep -F -q "$check" \
       && ! nft list chain inet filter forward 2>/dev/null | grep -F -q "$check"; then
        log "Adding: $check"
        eval "$cmd"
    else
        log "Already present: $check"
    fi
}

# Helper: ensure IPv4 masquerade for a subnet on LAN_IF with a marker comment
ensure_masquerade() {
    local subnet="$1" marker="$2"
    [ -n "$subnet" ] || return 0
    local expr="oifname \"${LAN_IF}\" ip saddr ${subnet} masquerade"
	# check for marker or exact expression
    if nft -a list chain ip nat postrouting | grep -qF "${marker}"; then
        log "masquerade marker present for ${subnet}"
        return 0
    fi
    if nft -a list chain ip nat postrouting | grep -qF "${expr}"; then
        log "masquerade rule already present for ${subnet} (no marker)"
        return 0
    fi
    log "Adding masquerade for ${subnet}"
    nft add rule ip nat postrouting oifname "${LAN_IF}" ip saddr "${subnet}" masquerade comment "\"${marker}\""
}

# --- Basic host input rules ---
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

# Allow DNS from LAN (IPv4)
add_rule "udp dport 53 iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET}" \
    "nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} udp dport 53 accept"

# Tailscale and WG DNS allow (IPv4)
for s in "${TAILSCALE_SUBNET}" "${WG_SUBNETS[@]}"; do
    [ -n "$s" ] || continue
    add_rule "udp dport 53 ip saddr ${s}" \
        "nft add rule inet filter input ip saddr ${s} udp dport 53 accept"
done

# Allow DNS from LAN (IPv6)
add_rule "udp dport 53 ip6 saddr ${LAN_SUBNET_V6}" \
    "nft add rule inet filter input ip6 saddr ${LAN_SUBNET_V6} udp dport 53 accept"

# Tailscale and WG DNS allow (IPv6)
for s in "${WG6_SUBNETS[@]}" "${TAILSCALE_SUBNET_V6}"; do
    [ -n "$s" ] || continue
    add_rule "udp dport 53 ip6 saddr ${s}" \
        "nft add rule inet filter input ip6 saddr ${s} udp dport 53 accept"
done

# Allow LAN-only ICMP echo to host
add_rule "ip saddr ${LAN_SUBNET} icmp type echo-request accept" \
    "nft add rule inet filter input ip saddr ${LAN_SUBNET} icmp type echo-request accept"
add_rule "ip6 saddr ${LAN_SUBNET_V6} icmpv6 type echo-request accept" \
    "nft add rule inet filter input ip6 saddr ${LAN_SUBNET_V6} icmpv6 type echo-request accept"

# Allow outbound DNS
add_rule "udp dport 53 accept" \
    "nft add rule inet filter output udp dport 53 accept"
add_rule "tcp dport 53 accept" \
    "nft add rule inet filter output tcp dport 53 accept"

# Allow outbound HTTP/HTTPS
add_rule "tcp dport 80 accept" \
    "nft add rule inet filter output tcp dport 80 accept"
add_rule "tcp dport 443 accept" \
    "nft add rule inet filter output tcp dport 443 accept"

# Allow outbound ICMP for diagnostics
add_rule "icmp type echo-request accept" \
    "nft add rule inet filter output icmp type echo-request accept"
add_rule "icmpv6 type echo-request accept" \
    "nft add rule inet filter output icmpv6 type echo-request accept"

# Allow outbound NTP
add_rule "udp dport 123 accept" \
    "nft add rule inet filter output udp dport 123 accept"


# --- WireGuard: open per-interface UDP ports and ensure IPv4 NAT per WG subnet ---
for i in $(seq 0 7); do
	bit=$((1 << i))
	if [ $((WG_MASK & bit)) -ne 0 ]; then
		iface="wg${i}"
		port="${WG_PORTS[$i]}"
		subnet="${WG_SUBNETS[$i]}"
		subnet6="${WG6_SUBNETS[$i]}"
		marker="managed-by=firewall-nft.sh:${iface}"

		# open UDP port for WireGuard (IPv4 + IPv6)
		add_rule "udp dport ${port} accept" \
			"nft add rule inet filter input udp dport ${port} ct state new,established accept"
		add_rule "udp dport ${port} accept ip6" \
			"nft add rule inet filter input udp dport ${port} ct state new,established accept"

		# ensure IPv4 masquerade for this WG subnet (skip if subnet empty)
		ensure_masquerade "${subnet}" "${marker}"

		# allow forwarding from WG subnet to LAN and to internet (IPv4)
		if [ -n "${subnet}" ]; then
			add_rule "iifname \"${iface}\" oifname \"${LAN_IF}\" ip saddr ${subnet} accept" \
				"nft add rule inet filter forward iifname \"${iface}\" oifname \"${LAN_IF}\" ip saddr ${subnet} accept"
			add_rule "iifname \"${iface}\" oifname != \"${LAN_IF}\" ip saddr ${subnet} accept" \
				"nft add rule inet filter forward iifname \"${iface}\" oifname != \"${LAN_IF}\" ip saddr ${subnet} accept"
		fi

		# allow forwarding for IPv6 (no NAT) and allow NDP/ICMPv6 essentials
		if [ -n "${subnet6}" ]; then
			add_rule "ip6 saddr ${subnet6} iifname \"${iface}\" oifname \"${LAN_IF}\" accept" \
				"nft add rule inet filter forward ip6 saddr ${subnet6} iifname \"${iface}\" oifname \"${LAN_IF}\" accept"
			add_rule "ip6 saddr ${subnet6} iifname \"${iface}\" oifname != \"${LAN_IF}\" accept" \
				"nft add rule inet filter forward ip6 saddr ${subnet6} iifname \"${iface}\" oifname != \"${LAN_IF}\" accept"
		fi
	fi
done

if [[ $UGOS -eq 0 ]]; then
    nft list ruleset > /etc/nftables.conf
    if systemctl enable --now nftables; then
        log "nftables service enabled and ruleset persisted"
    else
        log "WARNING: failed to enable/start nftables.service (rules applied live)"
    fi
else
    log "UGOS detected: skipping nftables.service and ruleset persistence"
fi

log "firewall-nft: rules ensured and persisted"
