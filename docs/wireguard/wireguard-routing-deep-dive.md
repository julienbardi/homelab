# WireGuard Routing Deep Dive
Homelab Network — Router + NAS Unified Control Plane

This document provides a full deep dive into routing internals for IPv4, IPv6, delegated prefixes, wg7, router tables, NAS tables, and failure analysis. It explains how packets move through the system and how routing invariants are enforced.

## 1. Purpose of Routing Deep Dive

Routing is the backbone of the WireGuard control plane.
It determines:

- how IPv4 packets move through router/NAS
- how IPv6 packets move through delegated prefixes
- how NAT66 rewrites IPv6
- how wg7 routes traffic
- how router and NAS maintain correct tables
- how drift is detected

This document formalizes routing behavior and failure modes.

## 2. Routing Roles

# Router Routing Roles
- IPv4 NAT
- IPv6 forwarding
- delegated prefix routing
- WireGuard server routing (wgs1)
- gateway for NAS

# NAS Routing Roles
- IPv6 NAT66
- delegated prefix routing
- IPv6 default route
- WireGuard client routing (wg7)
- gateway for wg7

# WireGuard Routing Roles
- IPv4/IPv6 routing inside tunnel
- delegated prefix routing for wg7
- IPv6 egress via NAS

## 3. IPv4 Routing Internals

IPv4 routing is simpler than IPv6.

# Router IPv4 Routing
Router performs IPv4 NAT for all LAN devices:

LAN → Router → NAT → ISP → Internet

WireGuard IPv4 routing:

wg7 → NAS → Router → NAT → ISP → Internet

# NAS IPv4 Routing
NAS does NOT NAT IPv4.
NAS routes IPv4 to router:

wg7 IPv4 → NAS → Router → NAT → Internet

# WireGuard IPv4 Routing
wg7 must have IPv4 route:

10.x.x.x/24 dev wg7

# IPv4 Routing Invariants

# Invariant V4-1 — Router must NAT IPv4
# Invariant V4-2 — NAS must NOT NAT IPv4
# Invariant V4-3 — wg7 must route IPv4 to NAS
# Invariant V4-4 — NAS must route IPv4 to router
# Invariant V4-5 — Router must route IPv4 to ISP

## 4. IPv6 Routing Internals

IPv6 routing is more complex due to delegated prefixes and NAT66.

# Router IPv6 Routing
Router must:

- maintain global IPv6
- provide delegated prefix
- forward IPv6
- route delegated prefix to NAS

# NAS IPv6 Routing
NAS must:

- maintain global IPv6
- maintain delegated prefix route
- maintain IPv6 default route
- apply NAT66
- route wg7 IPv6

# WireGuard IPv6 Routing
wg7 must:

- have IPv6 inside delegated prefix
- route IPv6 to NAS
- rely on NAS NAT66

# IPv6 Routing Invariants

# Invariant V6-1 — Router must forward IPv6
# Invariant V6-2 — Router must route delegated prefix
# Invariant V6-3 — NAS must maintain global IPv6
# Invariant V6-4 — NAS must maintain IPv6 default route
# Invariant V6-5 — NAS must apply NAT66
# Invariant V6-6 — wg7 must have IPv6 inside delegated prefix
# Invariant V6-7 — wg7 must route IPv6 to NAS

## 5. Delegated Prefix Deep Dive

Delegated prefix is provided by router via RA/PD:

Example:
2a02:xxxx:yyyy:zzzz::/64

Router responsibilities:

- advertise prefix