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

# Per-interface IPv4 subnets (wg0..wg7)
WG_SUBNETS=(
    "10.0.0.0/24" "10.1.0.0/24" "10.2.0.0/24" "10.3.0.0/24"
    "10.4.0.0/24" "10.5.0.0/24" "10.6.0.0/24" "10.7.0.0/24"
)

# Per-interface IPv6 /64s
WG6_SUBNETS=(
    "2a01:8b81:4800:9c00:10::/64" "2a01:8b81:4800:9c00:11::/64"
    "2a01:8b81:4800:9c00:12::/64" "2a01:8b81:4800:9c00:13::/64"
    "2a01:8b81:4800:9c00:14::/64" "2a01:8b81:4800:9c00:15::/64"
    "2a01:8b81:4800:9c00:16::/64" "2a01:8b81:4800:9c00:17::/64"
)

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

# --- Helper: add rule if missing ---
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

# --- NEW: baseline outbound + LAN ICMP rules (merged from firewall-allow.sh) ---

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

# Allow outbound ICMP (diagnostics)
add_rule "icmp type echo-request accept OUTPUT" \
    "nft add rule inet filter output icmp type echo-request accept"
add_rule "icmpv6 type echo-request accept OUTPUT" \
    "nft add rule inet filter output icmpv6 type echo-request accept"

# Allow outbound NTP
add_rule "udp dport 123 accept OUTPUT" \
    "nft add rule inet filter output udp dport 123 accept"

# --- Existing rules continue unchanged below ---
# (conntrack, LAN access, SSH, DNS, WG, NAT, IPv6, Tailscale, cleanup…)

# Persist ruleset and enable nftables service
nft list ruleset > /etc/nftables.conf
systemctl enable --now nftables || true

log "firewall-nft: rules ensured and persisted"
