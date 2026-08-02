# WireGuard IPv6 Contracts
Homelab Network — Router + NAS Unified Control Plane

This document defines the formal IPv6 contracts that govern the WireGuard control plane. These contracts specify IPv6 invariants, RA/PD rules, NAT66 behavior, routing guarantees, and failure modes. They ensure deterministic IPv6 operation for wg7 and all WireGuard clients.

## 1. Purpose of IPv6 Contracts

IPv6 is a first‑class citizen in the homelab WireGuard architecture.
It enables:

- global IPv6 egress for WireGuard clients
- NAT66 on NAS
- delegated prefix routing
- deterministic IPv6 behavior
- future IPv6‑only WireGuard

These contracts ensure IPv6 behaves predictably across router, NAS, and WireGuard interfaces.

## 2. IPv6 Roles

# Router IPv6 Roles
- Provide RA (Router Advertisements)
- Provide PD (Prefix Delegation)
- Maintain global IPv6 address
- Forward IPv6 traffic
- Act as IPv6 gateway for NAS

# NAS IPv6 Roles
- Receive RA/PD
- Maintain global IPv6 address
- Provide NAT66
- Act as IPv6 egress for wg7
- Maintain IPv6 default route

# WireGuard IPv6 Roles
- Provide IPv6 addressing for wg7
- Route IPv6 through NAS → Router → ISP
- Support IPv6‑only peers

## 3. Router IPv6 Contracts

# Contract R-V6-1 — Router must provide IPv6 RA
NAS must receive IPv6 prefix via SLAAC.

# Contract R-V6-2 — Router must provide IPv6 PD
NAS must receive delegated prefix.

# Contract R-V6-3 — Router must maintain global IPv6
Router must have a global IPv6 address on WAN.

# Contract R-V6-4 — Router must forward IPv6
IPv6 forwarding must be enabled.

# Contract R-V6-5 — Router must not NAT66
Router must forward IPv6 without NAT.

# Contract R-V6-6 — Router must advertise correct MTU
MTU must match ISP requirements.

# Contract R-V6-7 — Router must maintain IPv6 routes
IPv6 routing table must contain delegated prefix route.

## 4. NAS IPv6 Contracts

# Contract N-V6-1 — NAS must receive IPv6 RA
NAS must have a global IPv6 address on eth0.

# Contract N-V6-2 — NAS must maintain IPv6 default route
ip -6 route show must contain default route.

# Contract N-V6-3 — NAS must apply NAT66
NAT66 must be applied to IPv6 egress.

# Contract N-V6-4 — NAS must maintain delegated prefix
NAS must route delegated prefix correctly.

# Contract N-V6-5 — NAS must maintain IPv6 connectivity
curl -6 must succeed.

# Contract N-V6-6 — NAS must not advertise IPv6 prefixes
Only router may provide RA/PD.

# Contract N-V6-7 — NAS must maintain IPv6 MTU
MTU must match router advertisement.

## 5. WireGuard IPv6 Contracts

# Contract WG-V6-1 — wg7 must have IPv6 address
wg7 must have IPv6 address inside delegated prefix.

# Contract WG-V6-2 — wg7 must route IPv6 through NAS
wg7 → NAS → Router → ISP.

# Contract WG-V6-3 — wg7 must not NAT66
Only NAS may NAT66.

# Contract WG-V6-4 — wg7 must maintain IPv6 routes
ip -6 route show must contain wg7 subnet route.

# Contract WG-V6-5 — wg7 must support IPv6‑only peers
Peers may be IPv6‑only.

# Contract WG-V6-6 — wg7 must maintain correct MTU
MTU must match NAS and router.

## 6. NAT66 Contracts

# Contract NAT66-1 — NAT66 must occur only on NAS
Router must not NAT66.

# Contract NAT66-2 — NAT66 must use nftables
Chain: homelab_nat6 → postrouting → masquerade.

# Contract NAT66-3 — NAT66 must apply only to IPv6 egress
IPv4 NAT is router responsibility.

# Contract NAT66-4 — NAT66 must not break delegated prefix
Delegated prefix must remain routable.

# Contract NAT66-5 — NAT66 must preserve MTU
No fragmentation issues allowed.

## 7. IPv6 Routing Contracts

# Contract RT-V6-1 — Router must maintain delegated prefix route
ip -6 route show must contain delegated prefix.

# Contract RT-V6-2 — NAS must maintain IPv6 default route
Default route must point to router.

# Contract RT-V6-3 — wg7 must maintain IPv6 subnet route
wg7 subnet must be present.

# Contract RT-V6-4 — IPv6 must be reachable externally
curl -6 must succeed.

# Contract RT-V6-5 — IPv6 must be reachable internally