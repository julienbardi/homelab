#!/bin/sh
# pve-network-converge
# Deterministic IPv4 + IPv6 converge for Proxmox vmbr0
# Julien Bardi — Homelab Identity Contract

set -e

# Authoritative topology (override via environment if needed)
LAN_IPV4="10.89.12.4"
LAN_IPV4_PREFIX="24"
LAN_IPV4_GW="10.89.12.1"

LAN_IPV6="fd89:7a3b:42c0::4"
LAN_IPV6_PREFIX="64"
LAN_IPV6_GW="fd89:7a3b:42c0::1"

BRIDGE="vmbr0"
NIC="nic1"

TARGET="/etc/network/interfaces"
TMP="/tmp/interfaces.$$"

echo "🔧 pve-network-converge: enforcing IPv4 + IPv6 identity on ${BRIDGE}"

# Validate NIC
if ! ip link show "$NIC" >/dev/null 2>&1; then
    echo "❌ NIC '$NIC' does not exist — aborting"
    exit 1
fi

# Validate bridge
if ! ip link show "$BRIDGE" >/dev/null 2>&1; then
    echo "❌ Bridge '$BRIDGE' does not exist — aborting"
    exit 1
fi

# Generate new interfaces file
cat <<EOF > "$TMP"
auto lo
iface lo inet loopback

iface nic0 inet manual
iface nic1 inet manual

auto ${BRIDGE}
iface ${BRIDGE} inet static
        address ${LAN_IPV4}/${LAN_IPV4_PREFIX}
        gateway ${LAN_IPV4_GW}
        bridge-ports ${NIC}
        bridge-stp off
        bridge-fd 0

iface ${BRIDGE} inet6 static
        address ${LAN_IPV6}
        netmask ${LAN_IPV6_PREFIX}
        gateway ${LAN_IPV6_GW}

source /etc/network/interfaces.d/*
EOF

# Only replace if changed
if cmp -s "$TMP" "$TARGET"; then
    echo "✅ No changes — network identity already converged"
    rm -f "$TMP"
    exit 0
fi

echo "🔧 Applying network identity converge"
cp "$TMP" "$TARGET"
rm -f "$TMP"

echo "🔄 Restarting networking"
systemctl restart networking

echo "🟢 pve-network-converge complete"
