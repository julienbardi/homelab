#!/bin/sh
# Generated - DO NOT EDIT
set -e

# Exit quietly if WireGuard interface is not present
ip link show wgs1 >/dev/null 2>&1 || exit 0

# --- WireGuard UDP ingress (Port 51820) ---
iptables  -C INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || \
iptables  -I INPUT 1 -p udp --dport 51820 -j ACCEPT

ip6tables -C INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || \
ip6tables -I INPUT 1 -p udp --dport 51820 -j ACCEPT

# --- Per-peer LAN access (v4 + v6) ---

# Peer 10.89.101.240 / fd89:7a3b:42c0:101::65f0
iptables  -C FORWARD -i wgs1 -s 10.89.101.240/32 -o br0 -j ACCEPT 2>/dev/null || \
iptables  -A FORWARD -i wgs1 -s 10.89.101.240/32 -o br0 -j ACCEPT

ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 -o br0 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 -o br0 -j ACCEPT

# Peer 10.89.101.10 / fd89:7a3b:42c0:101::650a
iptables  -C FORWARD -i wgs1 -s 10.89.101.10/32 -o br0 -j ACCEPT 2>/dev/null || \
iptables  -A FORWARD -i wgs1 -s 10.89.101.10/32 -o br0 -j ACCEPT

ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::650a/128 -o br0 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wgs1 -s fd89:7a3b:42c0:101::650a/128 -o br0 -j ACCEPT

# Peer 10.89.101.133 / fd89:7a3b:42c0:101::6585
iptables  -C FORWARD -i wgs1 -s 10.89.101.133/32 -o br0 -j ACCEPT 2>/dev/null || \
iptables  -A FORWARD -i wgs1 -s 10.89.101.133/32 -o br0 -j ACCEPT

ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6585/128 -o br0 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6585/128 -o br0 -j ACCEPT

# Peer 10.89.101.37 / fd89:7a3b:42c0:101::6525
iptables  -C FORWARD -i wgs1 -s 10.89.101.37/32 -o br0 -j ACCEPT 2>/dev/null || \
iptables  -A FORWARD -i wgs1 -s 10.89.101.37/32 -o br0 -j ACCEPT

ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6525/128 -o br0 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6525/128 -o br0 -j ACCEPT

# --- Aggregated NAT and internet access (v4 + v6) ---

# NAT all WG peers to WAN (IPv4)
iptables -t nat -C POSTROUTING -s 10.89.101.0/24 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.89.101.0/24 -j MASQUERADE

# Allow WG peers to reach internet but not LAN (IPv4)
iptables  -C FORWARD -i wgs1 -s 10.89.101.0/24 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || \
iptables  -A FORWARD -i wgs1 -s 10.89.101.0/24 ! -d 10.89.12.0/24 -j ACCEPT

# Allow WG peers to reach internet but not LAN (IPv6)
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::/64 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || \
ip6tables -A FORWARD -i wgs1 -s fd89:7a3b:42c0:101::/64 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
