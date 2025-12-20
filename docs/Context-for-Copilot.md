# Context for Copilot (Final, Question‑Free, Code‑Accurate)
## Network topology and addressing
My LAN is `10.89.12.0/24`.
The NAS/subnet‑router is 10.89.12.4 on interface **eth0** (there is no bridge0 anymore).
The upstream router is `10.89.12.1` and delegates the global IPv6 prefix `2a01:8b81:4800:9c00::/64`
The NAS is the authoritative IPv6 router for that /64. It uses ndppd on eth0 to proxy NDP for all WireGuard and Tailscale clients.

The upstream router has static routes:
`
10.1.0.0/24 → 10.89.12.4
10.2.0.0/24 → 10.89.12.4
...
10.7.0.0/24 → 10.89.12.4
`
The router forwards UDP ports 51420–51427 to 10.89.12.4 for WireGuard.
The NAS provides DNS for LAN + WG + Tailscale clients (IPv4 + IPv6).

## WireGuard interface model
The NAS runs wg0–wg7, with a bitmask profile system:

Interface	Subnet	Port	Bits	Meaning
wg0	10.0.0.0/24	51420	n/a	Experimental
wg1	10.1.0.0/24	51421	001	LAN only
wg2	10.2.0.0/24	51422	010	Internet v4 only (NAT)
wg3	10.3.0.0/24	51423	011	LAN + Internet v4
wg4	10.4.0.0/24	51424	100	IPv6 only
wg5	10.5.0.0/24	51425	101	LAN v4 + IPv6
wg6	10.6.0.0/24	51426	110	Internet v4 + IPv6
wg7	10.7.0.0/24	51427	111	LAN + Internet v4 + IPv6

## IPv6 addressing for WG clients
Each WG interface has an IPv6 subnet:
`wgX → 2a01:8b81:4800:9c00:1X::/64`
Clients receive static IPv6 addresses inside that prefix.
The NAS uses ndppd to proxy NDP for the entire delegated /64 so upstream sees all WG/Tailscale IPv6 clients as reachable via eth0.

## Firewall and routing model
The NAS uses nftables, not iptables.

### Tables used
table inet filter

input (policy drop)

forward (policy drop)

output (policy accept)

table ip nat

postrouting (policy accept)

The script never touches vendor ip or ip6 filter tables.

### Rules implemented
- ct state related,established accept in input + forward
- LAN → NAS access (IPv4 + IPv6)
- WG host access (IPv4 + IPv6)
- WG forwarding rules per subnet
- WG handshake ports 51420–51427 on eth0
- NAT (MASQUERADE) for IPv4 Internet profiles: wg2, wg3, wg6, wg7
- No NAT66
- Tailscale forwarding + NAT (IPv4 only)
- GRO disabled on eth0
- IPv6 route for delegated prefix installed
- ndppd configured for delegated prefix

### Directionality
LAN hosts are allowed to initiate connections to WG clients (bidirectional), consistent with the nftables rules.

Key and config locations
Server private keys: /etc/wireguard/wgX.key

Server public keys: /etc/wireguard/wgX.pub

Server configs: /etc/wireguard/wgX.conf

Client configs: /etc/wireguard/clients/<name>-wgX.conf

Keys are generated on the NAS.

### Startup behavior
WireGuard interfaces are managed via systemd (wg-quick@wgX.service)

The subnet-router script is installed at /usr/local/bin/setup-subnet-router.nft.sh

A systemd service applies nftables + ndppd config at boot

make deps installs all required packages including ndppd, nftables, wireguard, unbound, tailscale, etc.

### IPv6 routing and RA model
The NAS does not send RAs on WireGuard interfaces

Clients use static IPv6 addresses inside their WG-specific /64

The NAS uses ndppd to proxy NDP for the entire delegated prefix

Upstream router only needs a route for the /64 → NAS

No SLAAC, no DHCPv6, no RA on WG interfaces

IPv6 full-tunnel works because:

NAS forwards IPv6

ndppd answers NDP

nftables allows forwarding

no NAT66

### Verification model
On NAS
```
nft list ruleset
systemctl status ndppd
ip -6 route
ip -6 neigh show proxy
wg show
tailscale status
```
On client
- LAN IPv4 reachability
- IPv4 Internet reachability (profiles with NAT)
- IPv6 global reachability
- IPv6 traceroute showing NAS as first hop
- DNS resolution (LAN + Internet)

### Cleanup model
- nftables rules can be removed by handle
- The script is idempotent and can be re-run safely
- Vendor tables are untouched
- No iptables/ip6tables rules are used
- No duplicate rules appear because add_rule() checks before insertion

## Summary
This is a modern, nftables-based, vendor-safe, IPv6-correct WireGuard subnet router running on a NAS at 10.89.12.4, with:
- delegated global IPv6 prefix
- ndppd for NDP proxying
- per-interface WG subnets
- bitmask-based access profiles
- IPv4 NAT only where required
- clean separation from vendor firewall
- deterministic routing for IPv4 and IPv6
- full LAN + Internet + IPv6 support depending on profile

Everything is aligned with the current code, current architecture, and current deployment model.