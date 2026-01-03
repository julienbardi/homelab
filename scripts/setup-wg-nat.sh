#!/bin/sh
# setup-wg-nat.sh
#
# IPv4 NAT for WireGuard Internet profiles on UGOS.
#
# IMPORTANT ARCHITECTURE OVERVIEW
#
# UGOS already implements host policy routing internally:
#
# | Traffic type        | Routing table / handler |
# |---------------------|-------------------------|
# | Host → LAN          | main                    |
# | Host → anything     | table_eth0 (UGOS)       |
# | Tailscale traffic   | table 52                |
# | WireGuard clients   | NAT only (this script)  |
#
# DO NOT add host policy routing here.
# DO NOT override UGOS routing tables.
#
# This script is intentionally limited to NAT only.
# It is safe to run repeatedly and will not affect SSH or LAN access.

set -eu

# ----------------------------
# Configuration
# ----------------------------

WAN_IF="eth0"

# WireGuard client subnets
WG_SUBNETS="
10.12.0.0/24
10.13.0.0/24
10.16.0.0/24
10.17.0.0/24
"

# ----------------------------
# Safety checks
# ----------------------------

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: must be run as root" >&2
	exit 1
fi

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "ERROR: missing required command: $1" >&2
		exit 1
	}
}

require_cmd iptables
require_cmd ip

ip link show dev "$WAN_IF" >/dev/null 2>&1 || {
	echo "ERROR: WAN interface not found: $WAN_IF" >&2
	exit 1
}

# ----------------------------
# Helpers
# ----------------------------

ensure_nat() {
	# -w 2 avoids xtables lock stalls on busy systems
	iptables -w 2 -t nat -C POSTROUTING "$@" 2>/dev/null || \
	iptables -w 2 -t nat -A POSTROUTING "$@"
}

# ----------------------------
# Execution
# ----------------------------

# NAT for IPv4 traffic originating on this host
ensure_nat -o "$WAN_IF" -j MASQUERADE

# NAT for IPv4 Internet traffic from WireGuard clients
for subnet in $WG_SUBNETS; do
	ensure_nat -s "$subnet" -o "$WAN_IF" -j MASQUERADE
done
