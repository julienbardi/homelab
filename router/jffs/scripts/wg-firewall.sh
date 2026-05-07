#!/bin/sh
# Generated - DO NOT EDIT
set -e

# Exit quietly if WireGuard interface is not present
ip link show wgs1 >/dev/null 2>&1 || exit 0

# Basic State Tracking
iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# --- wgs1 (Port 51820) ---
iptables -C INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
ip6tables -C INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || ip6tables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.240/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.240/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.240/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.240/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.240/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.240/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65f0/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.10/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.10/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::650a/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::650a/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.10/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.10/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.10/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.10/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::650a/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::650a/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.133/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.133/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6585/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::6585/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.133/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.133/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.133/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.133/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6585/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::6585/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.37/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.37/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6525/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::6525/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.37/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.37/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.37/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.37/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::6525/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::6525/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.241/32 -d 10.89.12.4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.241/32 -d 10.89.12.4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f1/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65f1/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.241/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.241/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.241/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.241/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65f1/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65f1/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.165/32 -d 10.89.12.4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.165/32 -d 10.89.12.4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65a5/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65a5/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.165/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.165/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.165/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.165/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65a5/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65a5/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.227/32 -d 10.89.12.4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.227/32 -d 10.89.12.4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65e3/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65e3/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.227/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.227/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.227/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.227/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::65e3/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::65e3/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
iptables -C FORWARD -i wgs1 -s 10.89.101.95/32 -d 10.89.12.4/32 -o br0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.95/32 -d 10.89.12.4/32 -o br0 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::655f/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::655f/128 -d fd89:7a3b:42c0::4/128 -o br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.89.101.95/32 -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING -s 10.89.101.95/32 -j MASQUERADE
iptables -C FORWARD -i wgs1 -s 10.89.101.95/32 ! -d 10.89.12.0/24 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i wgs1 -s 10.89.101.95/32 ! -d 10.89.12.0/24 -j ACCEPT
ip6tables -C FORWARD -i wgs1 -s fd89:7a3b:42c0:101::655f/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT 2>/dev/null || ip6tables -I FORWARD 2 -i wgs1 -s fd89:7a3b:42c0:101::655f/128 ! -d fd89:7a3b:42c0::/64 -j ACCEPT
