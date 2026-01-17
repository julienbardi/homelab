#!/bin/sh
# setup-wg-nat.sh
#
# IPv4 NAT for WireGuard Internet profiles on UGOS.
#
# This script enforces NAT only.
# It must not modify routing tables or policy rules.

set -eu

# ----------------------------
# Configuration
# ----------------------------

WAN_IF="eth0"

# WireGuard client subnets (LOCKED CONTRACT: /16 per interface)
WG_SUBNETS="
10.12.0.0/16
10.13.0.0/16
10.16.0.0/16
10.17.0.0/16
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
