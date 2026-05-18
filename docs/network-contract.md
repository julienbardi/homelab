# Network Contract

## IPv6 Addressing Model

- Internal IPv6 uses a ULA prefix: fd89:7a3b:42c0::/48 (stable, always present on all hosts)
- The NAS eth0 additionally receives the ISP-delegated global prefix via router RA (used solely as NAT66 egress route)
- No ISP‑delegated IPv6 prefixes may be assigned to WG clients, LAN hosts, or WG tunnel addresses
- No delegated IPv6 may appear in WireGuard configs, generated client configs, DNS records, or router scripts

## Delegated IPv6 - NAS Exception (NAT66 Egress Only)

The NAS eth0 is the sole exception to the delegated IPv6 prohibition:

- The NAS receives the ISP-delegated prefix from the router via RA/SLAAC
- This address is used **only** as the NAT66 masquerade source in `homelab_nat6`
- It is **never** advertised, forwarded, or exposed to WG clients, LAN hosts, or in any config file
- WG clients retain ULA tunnel addresses (fd89:7a3b:42c0:X::/64) at all times

## Delegated IPv6 Prohibition (Hard Invariant - still applies everywhere except NAS eth0)

Delegated IPv6 MUST NOT appear in:

- WireGuard configs (`AllowedIPs`, `Address`)
- WireGuard server configs (`Address`)
- dnsmasq configs
- nftables rules (except the NAT66 masquerade - which uses `saddr fd89::/48`, not the delegated prefix directly)
- Router scripts
- Caddy configs
- Any generated output
- Any committed file in the repository

## IPv6 Internet Access (wg7 - NAS terminated)

- wg7 clients route `::/0` through the tunnel (no native IPv6 leak)
- At the NAS exit: NAT66 masquerades client ULA to the NAS's global IPv6 (from router RA)
- The ISP sees the NAS's global IPv6 as the source - client location is hidden
- wgs1 (router-terminated) IPv6 internet remains unsupported (Asus merlin lacks ip6tables nat)

## Routing Authority

- The router is the sole routing authority for LAN and VPN clients
- The NAS and all other hosts MUST treat the router as the default gateway (IPv4 and IPv6)
- No host may advertise or route delegated IPv6 internally (except NAS NAT66 egress)

## WireGuard Isolation Model

- Each WireGuard interface is an isolated trust domain
- No WireGuard interface may route to another WireGuard interface
- No forwarding rules may bridge WG interfaces
- AllowedIPs MUST NOT overlap between interfaces

## IPv6 Internet Access

- Internal hosts and VPN clients do not receive delegated IPv6
- IPv6 Internet access, if provided, MUST use NAT66 on the NAS only (wg7 egress on NAS eth0)
- No delegated IPv6 may be forwarded to LAN or VPN clients

## Responsibility Boundaries

- Router: routing, IPv4 NAT (LAN -> WAN), firewall, exposure, RA advertisement (ULA + global prefix)
- NAS: config generation, key management, deployment, NAT66 egress for wg7 (table ip6 homelab_nat6)
- Hosts: assume legitimacy of received traffic but do not route

## Enforcement

- A Makefile guard MUST scan the repository for delegated IPv6 in configs and generated output
- NAS eth0 global IPv6 is exempt (it is not in any commited file; it is assigned at runtime by RA)
