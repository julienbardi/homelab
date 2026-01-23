# Network Contract

## IPv6 Addressing
- Internal IPv6 uses ULA only: fd89:7a3b:42c0::/48
- ISP‑delegated IPv6 prefixes are never used internally

## Prohibited Locations for Delegated IPv6
ISP‑delegated IPv6 must not appear in:
- WireGuard configurations
- dnsmasq configuration
- nftables rulesets
- Router scripts
- Caddy configuration

## IPv6 Internet Access
- IPv6 Internet access requires NAT66
- No delegated IPv6 is routed to internal hosts or VPN clients

## WireGuard Topology
- WireGuard interfaces never route to each other
- Each interface is an isolated trust domain

## Responsibility Boundaries
- The router enforces reachability and exposure
- Hosts assume legitimacy of received traffic

## Invariant Enforcement
- Any appearance of ISP‑delegated IPv6 is a bug
- Such occurrences must be treated as a regression and removed
