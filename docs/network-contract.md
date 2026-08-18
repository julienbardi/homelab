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
- nftables rules (except the NAT66 masquerade - which uses `saddr fd89:7a3b:42c0::/48` exclusively, never the delegated prefix)
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
- AllowedIPs MUST NOT overlap for either IPv4 or IPv6.

## IPv6 Internet Access

- Internal hosts and VPN clients do not receive delegated IPv6
- IPv6 Internet access, if provided, MUST use NAT66 on the NAS only (wg7 egress on NAS eth0)
- No delegated IPv6 may be forwarded to LAN or VPN clients

## Responsibility Boundaries

- Router: routing, IPv4 NAT (LAN -> WAN), firewall, exposure, RA advertisement (ULA + global prefix)
- NAS: config generation, key management, deployment, NAT66 egress for wg7 (table ip6 homelab_nat6)
- Hosts: assume legitimacy of received traffic but do not route
- The router MUST advertise the delegated IPv6 prefix via RA using dynamic WAN-learned values;
  no delegated prefix may appear statically in any router config file.

## Enforcement

- The guard MUST reject any literal IPv6 address in 2000::/3 (global unicast).
  Runtime NAS eth0 global IPv6 never appears in the repository and therefore
  requires no exemption.

## NAS IPv6 Forwarding and RA Acceptance

When `net.ipv6.conf.all.forwarding = 1` is active on the NAS (required for
WireGuard and Tailscale routing), the Linux kernel **automatically suppresses**
Router Advertisement reception on every interface (`accept_ra` defaults to 0).
Without a corrective override the NAS loses its IPv6 default route and all
wgN clients tunnelling IPv6 traffic hit a silent black hole.

**Invariant**: `net.ipv6.conf.eth0.accept_ra = 2` MUST be present in
`config/sysctl.d/99-homelab-forwarding.conf` and verified live by
`make ensure-accept-ra`.

- Value `1` is useless here (suppressed by `forwarding=1`).
- Value `2` = "accept RAs even when forwarding is enabled" (RFC 4861 §6.2.3).
- Only `eth0` (LAN) should carry this override; wgN interfaces never receive RAs.
- `net.ipv6.conf.all.accept_ra = 0`
- `net.ipv6.conf.default.accept_ra = 0`
- `net.ipv6.conf.eth0.forwarding = 0`
- All WireGuard interfaces (wg0–wg15) inherit forwarding=1 via `net.ipv6.conf.all.forwarding = 1`.

## WireGuard Public Endpoint

All generated WireGuard client configs MUST use the bare domain `bardi.ch`
as the peer endpoint, **not** a sub-domain such as `router.bardi.ch`.

Rationale:
- Unbound split-horizon DNS resolves `router.bardi.ch` to `10.89.12.1` (router
  LAN IP) for clients on the LAN segment.
- wg7 (and other NAS-hosted interfaces) run on `10.89.12.4`, **not** on
  `10.89.12.1`.  Sending a handshake to the router's LAN IP on a NAS port
  produces a silent black hole.
- `bardi.ch` has no split-horizon override → always resolves to the WAN IP via
  public DNS → consistent from both LAN (NAT hairpin) and WAN.

The router MUST forward each WireGuard UDP port from WAN to the appropriate
host/port (`wgs1:51819` stays on the router; `wg1–wg15:5142N` forward to NAS).
