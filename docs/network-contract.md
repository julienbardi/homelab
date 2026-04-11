# Network Contract

## IPv6 Addressing Model
- Internal IPv6 uses a single ULA prefix: fd89:7a3b:42c0::/48
- No ISP‑delegated IPv6 prefixes may appear anywhere in the repository
- No delegated IPv6 may be assigned, routed, advertised, or leaked internally

## Delegated IPv6 Prohibition (Hard Invariant)
Delegated IPv6 MUST NOT appear in:
- WireGuard configs
- dnsmasq configs
- nftables rules
- Router scripts
- Caddy configs
- Any generated output
- Any committed file in the repository

Any occurrence is a regression and must be removed immediately.

## Routing Authority
- The router is the sole routing authority for LAN and VPN clients
- The NAS and all other hosts MUST treat the router as the default gateway
- No host may advertise or route delegated IPv6 internally

## WireGuard Isolation Model
- Each WireGuard interface is an isolated trust domain
- No WireGuard interface may route to another WireGuard interface
- No forwarding rules may bridge WG interfaces
- AllowedIPs MUST NOT overlap between interfaces

## IPv6 Internet Access
- Internal hosts and VPN clients do not receive delegated IPv6
- IPv6 Internet access, if provided, MUST use NAT66 on the router only
- No delegated IPv6 may be forwarded to LAN or VPN clients

## Responsibility Boundaries
- Router: routing, NAT, firewall, exposure
- NAS: config generation, key management, deployment
- Hosts: assume legitimacy of received traffic but do not route

## Enforcement
- A Makefile guard MUST scan the repository for delegated IPv6
- Any match MUST fail the build
