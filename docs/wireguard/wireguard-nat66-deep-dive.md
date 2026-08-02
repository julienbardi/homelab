# WireGuard NAT66 Deep Dive
Homelab Network — Router + NAS Unified Control Plane

This document provides a full deep dive into NAT66 internals, nftables chains, packet flow, delegated prefix behavior, IPv6 routing, and failure analysis. NAT66 is a critical part of the homelab WireGuard architecture because wg7 uses IPv6 egress through the NAS.

## 1. Purpose of NAT66

NAT66 is used to allow IPv6 packets from wg7 to exit the NAS using the NAS’s global IPv6 address.
It is required because:

- wg7 uses a delegated IPv6 prefix (fd00:7::/64 or similar)
- delegated prefixes are not globally routable
- NAS must rewrite source IPv6 to its global IPv6
- router must forward IPv6 without NAT
- ISP expects globally routable IPv6

NAT66 is the IPv6 equivalent of IPv4 masquerade, but without port translation.

## 2. NAT66 Responsibilities

# NAS Responsibilities
- Maintain global IPv6 address
- Apply NAT66 to IPv6 egress
- Maintain IPv6 default route
- Route delegated prefix
- Provide IPv6 egress for wg7

# Router Responsibilities
- Provide RA/PD
- Forward IPv6
- Must NOT NAT66

# WireGuard Responsibilities
- Provide IPv6 addressing for wg7
- Route IPv6 through NAS → Router → ISP

## 3. NAT66 Packet Flow

Full IPv6 packet flow:

wg7 → NAS → NAT66 → Router → ISP → Internet

ASCII diagram:

wg7 ──► NAS ──► NAT66 ──► Router ──► ISP ──► Internet

# Step-by-step:

1. Client sends IPv6 packet through WireGuard tunnel
2. wg7 receives packet
3. NAS routes packet to eth0
4. NAT66 rewrites source IPv6 to NAS global IPv6
5. Router forwards packet
6. ISP forwards packet
7. Internet receives packet

## 4. NAT66 nftables Chain

NAT66 is implemented using nftables:

table ip6 homelab_nat6 {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "eth0" masquerade
    }
}

# Key points:

- NAT66 occurs only in postrouting
- NAT66 applies only to IPv6
- NAT66 applies only when outgoing interface is eth0
- NAT66 uses masquerade (no port translation)
- NAT66 rewrites source IPv6 to NAS global IPv6

## 5. Delegated Prefix Behavior

Router provides delegated prefix via RA/PD:

- NAS receives prefix (e.g., 2a02:xxxx:yyyy:zzzz::/64)
- NAS assigns IPv6 to wg7 (e.g., 2a02:xxxx:yyyy:zzzz::7/64)
- wg7 IPv6 is NOT globally routable
- NAT66 rewrites wg7 IPv6 to NAS global IPv6

Delegated prefix must:

- be stable
- be routable internally
- not be used directly for egress

## 6. IPv6 Routing Internals

# Router IPv6 Routing
Router must maintain:

- global IPv6
- delegated prefix route
- IPv6 forwarding

# NAS IPv6 Routing
NAS must maintain:

- global IPv6
- delegated prefix route
- IPv6 default route
- NAT66

# wg7 IPv6 Routing
wg7 must maintain:

- IPv6 address inside delegated prefix
- IPv6 route for wg7 subnet

## 7. NAT66 MTU Behavior

MTU must be consistent across:

- wg7
- NAS eth0
- router WAN
- ISP

If MTU mismatches occur:

- IPv6 packets fragment
- NAT66 may drop fragments
- IPv6 egress fails

## 8. NAT66 Failure Modes

# Failure N66-F1 — NAT66 chain missing
Symptoms: IPv6 egress fails
Fix: make nft-apply

# Failure N66-F2 — NAS has no global IPv6
Symptoms: ip -6 addr show dev eth0 shows only link-local
Fix: router RA/PD broken

# Failure N66-F3 — Missing IPv6 default route
Symptoms: IPv6 unreachable
Fix: router RA/PD broken

# Failure N66-F4 — wg7 IPv6 missing
Symptoms: wg7 has no IPv6 address
Fix: make wg-install-nas

# Failure N