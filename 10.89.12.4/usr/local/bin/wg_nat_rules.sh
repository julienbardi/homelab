#!/usr/bin/env bash
# Script: wg_nat_rules.sh
# to deploy use 
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/wg_nat_rules.sh /usr/local/bin/wg_nat_rules.sh
# Helper script to execute complex PostUp/PostDown commands (he parser on this particular NAS is so strict that it rejects any space in the value portion of a PostUp or PostDown key. It stops reading the value at the very first space)
# Arguments: $1 = interface name (%i), $2 = action (up/down)
set -euo pipefail

iface="$1"
action="$2"
# Note: These variables must be redefined here as they are no longer sourced from wg.sh
NAS_LAN_IFACE="bridge0"
LAN_SUBNET="10.89.12.0/24"
num=${iface#wg} # Extract interface number (e.g., '1' from 'wg1')
wg_ipv4_subnet="10.$num.0.0/24"
wg_ipv6_subnet="fd10:$num::/64"

if [[ "$action" == "up" ]]; then
    echo "Running PostUp for $iface..."
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    # IPv4 FORWARD
    iptables-legacy -A FORWARD -i "$iface" -j ACCEPT
    iptables-legacy -A FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # IPv4 NAT
    iptables-legacy -t nat -A POSTROUTING -s "$wg_ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE
    # IPv6 FORWARD
    ip6tables-legacy -A FORWARD -i "$iface" -j ACCEPT
    ip6tables-legacy -A FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # IPv6 NAT
    ip6tables-legacy -t nat -A POSTROUTING -s "$wg_ipv6_subnet" -o "$NAS_LAN_IFACE" -j MASQUERADE

elif [[ "$action" == "down" ]]; then
    echo "Running PostDown for $iface..."
    # CLEANUP RULES
    iptables-legacy -D FORWARD -i "$iface" -j ACCEPT
    iptables-legacy -D FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables-legacy -t nat -D POSTROUTING -s "$wg_ipv4_subnet" -o "$NAS_LAN_IFACE" ! -d "$LAN_SUBNET" -j MASQUERADE
    ip6tables-legacy -D FORWARD -i "$iface" -j ACCEPT
    ip6tables-legacy -D FORWARD -o "$iface" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ip6tables-legacy -t nat -D POSTROUTING -s "$wg_ipv6_subnet" -o "$NAS_LAN_IFACE" -j MASQUERADE
fi