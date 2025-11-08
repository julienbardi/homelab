#!/bin/bash
# Script: firewall.sh
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/firewall.sh /usr/local/bin/firewall.sh

set -euo pipefail
# source "/home/julie/homelab/scripts/config/homelab.env"

# Require root for all scripts
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run with sudo/root." >&2
  exit 1
fi

# --- Variables (Self-sourced for persistence) ---
WG_INTERFACE=wg0
WG_PORT=51822
WG_SUBNET=10.4.0.0/24

DNS_PORT=53
SSH_PORT_DEFAULT=22  # Standard SSH Port
SSH_PORT_CUSTOM=2222 # Your Custom SSH Port

LAN_SUBNET=10.89.12.0/24
LAN_SUBNET_IPV6="fd10:8912:0000:C::/64" # Your stable ULA subnet
TAILSCALE_INTERFACE=tailscale0
TAILSCALE_SUBNET=100.64.0.0/10

# --- General Firewall Flush ---
echo "⚙️ Flushing existing IPv4 and IPv6 rules..."
iptables -F
iptables -t nat -F
iptables -X
ip6tables -F
ip6tables -X

# =========================================================================
# === IPV4 RULES (IPTABLES) ===
# =========================================================================

echo "➡️ Setting IPv4 policies and base rules..."

# Default policies (Secure by default)
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback and established connections
iptables -A INPUT -i lo -j ACCEPT
# CRITICAL: Allows return traffic for established outgoing connections (e.g., recursive DNS queries)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 🛑 TEMPORARY: OPEN ALL PORTS FOR LAN SUBNET
echo "🛑 TEMPORARY: Opening ALL TCP/UDP ports for ${LAN_SUBNET}"
iptables -A INPUT -p tcp -s ${LAN_SUBNET} -j ACCEPT
iptables -A INPUT -p udp -s ${LAN_SUBNET} -j ACCEPT
# -----------------------------------------------

# Allow SSH from LAN (Ports 22 and 2222)
iptables -A INPUT -p tcp --dport ${SSH_PORT_DEFAULT} -s ${LAN_SUBNET} -j ACCEPT
iptables -A INPUT -p tcp --dport ${SSH_PORT_CUSTOM} -s ${LAN_SUBNET} -j ACCEPT

# Allow NAS Web UI from LAN (Port 9999)
iptables -A INPUT -p tcp --dport 9999 -s ${LAN_SUBNET} -j ACCEPT

# Allow DNS from LAN/trusted subnets
iptables -A INPUT -p udp --dport ${DNS_PORT} -s ${LAN_SUBNET} -j ACCEPT
iptables -A INPUT -p tcp --dport ${DNS_PORT} -s ${LAN_SUBNET} -j ACCEPT
# Allow DNS from WireGuard/Tailscale subnets
iptables -A INPUT -p udp --dport ${DNS_PORT} -s ${WG_SUBNET} -j ACCEPT
iptables -A INPUT -p udp --dport ${DNS_PORT} -s ${TAILSCALE_SUBNET} -j ACCEPT

# Allow incoming WireGuard traffic
iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

# Allow Tailscale interface (full access for simplicity/trust)
iptables -A INPUT -i ${TAILSCALE_INTERFACE} -j ACCEPT

# NAT for WireGuard subnet
WAN_IF=$(ip route | awk '/default/ {print $5; exit}')
iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE

# =========================================================================
# === IPV6 RULES (IP6TABLES) - FIX FOR UBOUND TIMEOUT ===
# =========================================================================

echo "➡️ Setting IPv6 policies and base rules (CRITICAL for Ubound)..."

# Default policies (Secure by default)
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# Allow loopback and established connections
ip6tables -A INPUT -i lo -j ACCEPT
# CRITICAL: Allows return traffic for established outgoing connections. This solves the Ubound hang/timeout.
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from ULA subnet (Ports 22 and 2222)
ip6tables -A INPUT -p tcp --dport ${SSH_PORT_DEFAULT} -s ${LAN_SUBNET_IPV6} -j ACCEPT
ip6tables -A INPUT -p tcp --dport ${SSH_PORT_CUSTOM} -s ${LAN_SUBNET_IPV6} -j ACCEPT

# Allow DNS (Ubound on port 53) from ULA subnet
ip6tables -A INPUT -p udp --dport ${DNS_PORT} -s ${LAN_SUBNET_IPV6} -j ACCEPT
ip6tables -A INPUT -p tcp --dport ${DNS_PORT} -s ${LAN_SUBNET_IPV6} -j ACCEPT

# Allow incoming WireGuard traffic (IPv6)
ip6tables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

# Allow Tailscale interface (full access for simplicity/trust)
ip6tables -A INPUT -i ${TAILSCALE_INTERFACE} -j ACCEPT

echo "✅ Firewall rules loaded successfully. The Ubound timeout issue should now be resolved by these rules."
echo ""

# =========================================================================
# === CHECKLIST OUTPUTS ===
# =========================================================================

echo "========================================================================="
echo "--- 📝 UGOS ROUTER CHECKLIST ---"
echo "========================================================================="
echo "This checklist covers the high-level configuration requirements for the router."
echo ""
echo "## 1. ULA DNS Advertising"
echo "   - ACTION: Verify the router is distributing the stable ULA DNS address to all clients."
echo "   - STATUS: Must be configured in the router's IPv6 settings."
echo ""
echo "## 2. Route Integrity"
echo "   - ACTION: Ensure no static IPv6 route is interfering with the NAS's ability to reach the internet."
echo "   - STATUS: Must be checked in the router's Static Route configuration."
echo ""
echo "========================================================================="
echo "--- 💻 ASUS RT-AX86U @ https://10.89.12.1 Specific Checks ---"
echo "========================================================================="
echo "These are the exact values to verify in the router's web interface (IPv6 -> Static Route tab):"
echo ""
echo "## Router DNS Advertisement (IPv6 Settings):"
echo "  [ ] VERIFY: Primary IPv6 DNS Server is set to: **fd10:8912:0000:C::4**"
echo "  [ ] VERIFY: Secondary IPv6 DNS Server is set to: **fe80::127c:61ff:fe42:c2c0** (Router LLA)"
echo ""
echo "## Critical Route Cleanup (Prevents Route Failure):"
echo "  [ ] **VERIFY & DELETE**: Locate the 'IPv6 Static Route' section on the router."
echo "  [ ] ACTION: Find the entry where the **Gateway** is **fd10:8912:0:c::1**."
echo "  [ ] ACTION: **DELETE** this entry and **APPLY** the changes."
echo "  [ ] EXPLANATION: This static route wrongly directs internet traffic to an address that is not the router, and is the reason for the earlier 'No route to host' errors."
echo ""