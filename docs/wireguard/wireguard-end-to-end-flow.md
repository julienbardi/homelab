# WireGuard End-to-End Flow
Homelab Network — Router + NAS Unified Control Plane

This document provides a complete end‑to‑end packet flow walkthrough for IPv4, IPv6, NAT, NAT66, wg7, router, NAS, and WireGuard peers. It explains how packets traverse the system from client → wg7 → NAS → router → ISP → internet.

## 1. Purpose of End-to-End Flow

End‑to‑end flow analysis ensures:

- correct routing
- correct NAT/NAT66 behavior
- correct IPv6 delegated prefix usage
- correct WireGuard interface behavior
- correct router/NAS separation
- deterministic packet movement

This is the full walkthrough of how packets travel through the homelab WireGuard architecture.

## 2. System Overview Diagram

ASCII overview:

Client
  │
  ▼
WireGuard Tunnel
  │
  ▼
wg7 (NAS)
  │
  ▼
NAS Routing
  │
  ├── IPv4 → Router NAT → ISP
  │
  └── IPv6 → NAT66 → Router → ISP
  ▼
Internet

## 3. IPv4 End-to-End Flow

IPv4 flow is straightforward:

Client → wg7 → NAS → Router → NAT → ISP → Internet

Step-by-step:

1. Client sends IPv4 packet through WireGuard tunnel
2. wg7 receives packet
3. NAS routes packet to router
4. Router performs IPv4 NAT
5. Router sends packet to ISP
6. ISP sends packet to internet

# IPv4 Routing Invariants

# V4-1 — wg7 must route IPv4 to NAS
# V4-2 — NAS must route IPv4 to router
# V4-3 — Router must NAT IPv4
# V4-4 — Router must route IPv4 to ISP
# V4-5 — IPv4 must be reachable externally

## 4. IPv6 End-to-End Flow

IPv6 flow is more complex due to delegated prefixes and NAT66.

Client → wg7 → NAS → NAT66 → Router → ISP → Internet

Step-by-step:

1. Client sends IPv6 packet through WireGuard tunnel
2. wg7 receives packet
3. wg7 assigns IPv6 inside delegated prefix
4. NAS routes packet to eth0
5. NAT66 rewrites source IPv6 to NAS global IPv6
6. Router forwards IPv6
7. ISP forwards IPv6
8. Internet receives packet

# IPv6 Routing Invariants

# V6-1 — wg7 must have IPv6 inside delegated prefix
# V6-2 — NAS must maintain global IPv6
# V6-3 — NAS must apply NAT66
# V6-4 — Router must forward IPv6
# V6-5 — IPv6 must be reachable externally

## 5. WireGuard Tunnel Flow

WireGuard tunnel flow is identical for IPv4 and IPv6:

Client → encrypted WG packet → wgs1 → decrypted → routed

ASCII:

Client
  │ encrypted
  ▼
Router wgs1
  │ decrypted
  ▼
Router routing
  │
  ▼
NAS / LAN / Internet

# WireGuard Tunnel Invariants

# WG-1 — Router must accept UDP/51820
# WG-2 — Router must decrypt packets
# WG-3 — Router must route packets
# WG-4 — Router must forward IPv6
# WG-5 — Router must NAT IPv4

## 6. Delegated Prefix Flow

Delegated prefix is provided by router via RA/PD:

Router → NAS → wg7

Example prefix:
2a02:xxxx:yyyy:zzzz::/64

Flow:

1. Router advertises prefix
2. NAS receives prefix
3. NAS assigns IPv6 to wg7
4. wg7 uses delegated prefix for IPv6
5. NAT66 rewrites delegated prefix to NAS global IPv6

# Delegated