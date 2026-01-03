#!/bin/sh
# setup-wg-nat.sh
# IPv4 NAT for WireGuard Internet profiles (iptables-nft owned)

set -euo pipefail

WAN_IF="eth0"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must be run as root (use sudo or make router-nat)" >&2
    exit 1
fi

# IPv4-Internet bitmask profiles only
# IPv4-Internet WireGuard subnets
# wg2: 10.12.0.0/24
# wg3: 10.13.0.0/24
# wg6: 10.16.0.0/24
# wg7: 10.17.0.0/24
WG_INET4_SUBNETS="
10.12.0.0/24
10.13.0.0/24
10.16.0.0/24
10.17.0.0/24
"
for subnet in $WG_INET4_SUBNETS; do
	iptables -t nat -C POSTROUTING -s "$subnet" -o "$WAN_IF" -j MASQUERADE 2>/dev/null || \
	iptables -t nat -A POSTROUTING -s "$subnet" -o "$WAN_IF" -j MASQUERADE
done
