#!/usr/bin/env bash
# firewall-nft.sh
# Idempotent nft-based firewall for NAS host aligned with mk/40_wireguard.mk
set -euo pipefail

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

# --- Variables (adjust only if your environment differs) ---
LAN_IF="bridge0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
TAILSCALE_IF="tailscale0"
TAILSCALE_SUBNET="100.64.0.0/10"

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
    if ! nft -a list ruleset | grep -F -q "$check"; then
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
    if nft -a list chain ip nat postrouting | grep -qF "${marker}"; then
        log "masquerade marker present for ${subnet}"
        return 0
    fi
    if nft -a list chain ip nat postrouting | grep -qF "${expr}"; then
        log "masquerade rule already present for ${subnet} (no marker)"
        return 0
    fi
    log "Adding masquerade for ${subnet}"
    nft add rule ip nat postrouting oifname "${LAN_IF}" ip saddr "${subnet}" masquerade comment "${marker}"
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

# Allow LAN-only ICMP echo to host
add_rule "ip saddr ${LAN_SUBNET} icmp type echo-request accept" \
    "nft add rule inet filter input ip saddr ${LAN_SUBNET} icmp type echo-request accept"
add_rule "ip6 saddr ${LAN_SUBNET_V6} icmpv6 type echo-request accept" \
    "nft add rule inet filter input ip6 saddr ${LAN_SUBNET_V6} icmpv6 type echo-request accept"

# Allow outbound DNS
add_rule "udp dport 53 accept OUTPUT" \
    "nft add rule inet filter output udp dport 53 accept"
add_rule "tcp dport 53 accept OUTPUT" \
    "nft add rule inet filter output tcp dport 53 accept"

# Allow outbound HTTP/HTTPS
add_rule "tcp dport 80 accept OUTPUT" \
    "nft add rule inet filter output tcp dport 80 accept"
add_rule "tcp dport 443 accept OUTPUT" \
    "nft add rule inet filter output tcp dport 443 accept"

# Allow outbound ICMP for diagnostics
add_rule "icmp type echo-request accept OUTPUT" \
    "nft add rule inet filter output icmp type echo-request accept"
add_rule "icmpv6 type echo-request accept OUTPUT" \
    "nft add rule inet filter output icmpv6 type echo-request accept"

# Allow outbound NTP
add_rule "udp dport 123 accept OUTPUT" \
    "nft add rule inet filter output udp dport 123 accept"

# --- WireGuard: open per-interface UDP ports and ensure IPv4 NAT per WG subnet ---
# (unchanged below)
