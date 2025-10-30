#!/bin/bash
set -euo pipefail
source "/home/julie/homelab/scripts/config/homelab.env"

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -X
ip6tables -F
ip6tables -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback and established connections
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from LAN
iptables -A INPUT -p tcp --dport 22 -s ${LAN_SUBNET} -j ACCEPT

# Allow DNS
iptables -A INPUT -p udp --dport ${DNSMASQ_PORT} -j ACCEPT

# Allow WireGuard
iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

# Allow Tailscale interface
iptables -A INPUT -i ${TAILSCALE_INTERFACE} -j ACCEPT

# NAT for WireGuard subnet
WAN_IF=$(ip route | awk '/default/ {print $5; exit}')
iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE
