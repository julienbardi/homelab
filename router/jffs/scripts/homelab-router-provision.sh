#!/bin/sh
# homelab-router-provision.sh
# Stand-alone IPv6 ULA + RA + NVRAM converge for ASUSWRT-Merlin

set -e

ULA_PREFIX="fd89:7a3b:42c0::/48"
ROUTER_ULA_IP="fd89:7a3b:42c0::1"
LAN_PREFIXLEN=64

echo "🔧 Restoring IPv6 ULA provisioning"

# Enable ULA
nvram set ipv6_ula_enable=1
nvram set ipv6_ula_prefix="$ULA_PREFIX"

# Set router LAN IPv6 address
nvram set ipv6_lan_addr="$ROUTER_ULA_IP"
nvram set ipv6_lan_prefix="$LAN_PREFIXLEN"

echo "🔧 Restoring RA policy"
nvram set ipv6_accept_ra=2

echo "🔧 Restoring SSH invariants"
nvram set ssh_wan=0
nvram set ssh_lan=1

echo "🔧 Installing DHCPv6-PD hook"
mkdir -p /jffs/scripts
cat << 'EOF' > /jffs/scripts/dhcp6c-state
#!/bin/sh
service restart_dnsmasq
EOF
chmod 755 /jffs/scripts/dhcp6c-state

echo "🔧 Committing NVRAM"
nvram commit

echo "🔧 Restarting services"
service restart_dnsmasq
service restart_radvd || true

echo "🟢 Router IPv6 ULA provisioning complete"
