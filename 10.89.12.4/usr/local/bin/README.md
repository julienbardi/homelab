
Prerequisites for firewall-simple-wireguard.sh

Run this to check for the non‑legacy tools (one command; paste the output):

for b in iptables iptables-restore iptables-save ip6tables ip6tables-restore ip6tables-save ss ping; do
  if command -v "$b" >/dev/null 2>&1; then
    echo "OK:      $b -> $(command -v $b)"
  else
    echo "MISSING: $b"
  fi
done

MISSING: iptables 
MISSING: iptables-restore
MISSING: iptables-save
MISSING: ip6tables
MISSING: ip6tables-restore
MISSING: ip6tables-save
OK: ss -> /usr/bin/ss
OK: ping -> /usr/bin/ping

sudo apt install -y iptables

julie@nas:~/homelab/10.89.12.4/usr/local/bin$ sudo apt install -y iptables
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
iptables is already the newest version (1.8.9-2).
0 upgraded, 0 newly installed, 0 to remove and 192 not upgraded.

Run this to check for the iptables binaries as root (paste the output here):
for b in /sbin/iptables /sbin/iptables-restore /sbin/iptables-save /sbin/ip6tables /sbin/ip6tables-restore /sbin/ip6tables-save /usr/sbin/iptables* /usr/sbin/ip6tables*; do
  if [[ -e $b ]]; then ls -l "$b"; else echo "NOTFOUND: $b"; fi
done


________________

Context for Copilot

Prompt describing your network, goals and current state
My LAN is 10.89.12.0/24; the router is 10.89.12.1 and advertises the global IPv6 prefix 2a01:8b81:4800:9c00::/64 (prefix length 64). The router has static routes that point 10.1.0.0/24 → 10.89.12.4 (metric 1) and similarly routes 10.2.0.0/24 through 10.7.0.0/24 via gateway 10.89.12.4. The router forwards UDP ports 51420–51427 to 10.89.12.4 for WireGuard.

The NAS at 10.89.12.4 runs WireGuard and acts as a DNS server resolving LAN and internet names via both IPv4 and IPv6. I will run multiple WireGuard interfaces on the NAS:

wg0 — experimentation (profiles can be tested here)

wg1..wg7 — production test interfaces with these mappings:

wg1: subnet 10.1.0.0/24, port 51421, profile bits 001 (LAN only)

wg2: subnet 10.2.0.0/24, port 51422, profile bits 010 (Internet only)

wg3: subnet 10.3.0.0/24, port 51423, profile bits 011 (LAN + Internet)

wg4: subnet 10.4.0.0/24, port 51424, profile bits 100 (IPv6 only)

wg5: subnet 10.5.0.0/24, port 51425, profile bits 101 (LAN v4 + IPv6)

wg6: subnet 10.6.0.0/24, port 51426, profile bits 110 (Internet v4 + IPv6)

wg7: subnet 10.7.0.0/24, port 51427, profile bits 111 (LAN + Internet + IPv6)

Key and config locations on NAS (will be generated on the NAS):

Server private keys: /etc/wireguard/wg1.key (wg1 example) — analogous for wg2..wg7

Server public keys: /etc/wireguard/wg1.pub

Server interface config files: /etc/wireguard/wg1.conf (wg1 example)

Client configs: /etc/wireguard/clients/julie-wg1.conf (client named julie for wg1)

IPv6 addressing and routing plan

Clients will use the router-advertised global prefix 2a01:8b81:4800:9c00::/64 (not ULA) for their IPv6 addresses.

The testing matrix will exercise whether each wgX interface provides LAN IPv4 access, IPv4 Internet access (NAT or routed depending on profile), and/or IPv6 (::/0) access via the NAS.

Firewall tooling and kernel state

Authoritative firewall tooling on the NAS: iptables-legacy (IPv4) and ip6tables-legacy (IPv6) — confirmed working.

Kernel supports ip6tables nat table: yes.

net.ipv4.ip_forward = 1 and net.ipv6.conf.all.forwarding = 1 are already enabled.

Deliverables requested Please generate for me:

Server wgX configs and one client example per profile (wg1..wg7 + wg0 example).

Idempotent firewall rules (iptables-legacy / ip6tables-legacy) to implement the bitmask truth table: FORWARD accept rules, RELATED/ESTABLISHED, and POSTROUTING MASQUERADE where needed — each rule added only if it does not already exist. Include IPv6 equivalents where applicable.

IPv6 routing steps and notes required to make global-prefix full-tunnel work for v6 (RA/route setup, whether SLAAC/managed config or static assignment for clients through WG).

Verification commands to run on NAS and a client to confirm behavior per profile.

Safe cleanup commands to remove a rule by chain and number, and a small idempotent script to remove duplicate rules from FORWARD or POSTROUTING if duplicates exist.

Open questions / items I need from you (please answer these so I can produce exact configs and rules)

Confirm NAS LAN and WAN interface names (example: bridge0 for LAN, eth0 for WAN). If you’re using bridge0 for LAN and eth0 for WAN, say so.

For each wg interface: do you want the server to NAT client IPv4 traffic to the WAN IP when "Internet access" bit is set, or do you prefer routing without NAT relying on router static routes? (Options: NAT=yes or NAT=no. Current router static routes exist for 10.1.0.0/24 → 10.89.12.4, etc., so routing may be preferred for LAN-reachable subnets.)

For IPv6 full-tunnel behavior: do you want clients to receive addresses in the advertised global prefix via static assignment (derived from the prefix) or do you want the NAS to advertise RA/assign addresses (RAs/ND proxy) on behalf of clients? (Options: static-per-client, managed-by-NAS with RA, or proxying on router.)

Do you want LAN hosts to be allowed to initiate connections to WG clients (bidirectional), or only client-initiated sessions (uni-directional from clients to LAN)?

Will you create keys yourself and paste public keys per client, or do you want me to use placeholders and indicate exactly where to insert keys?

Do you want wg-quick/systemd unit enablement instructions for automatic startup on boot?

Any additional constraints (e.g., firewall default policies, UFW/firewalld also installed and managing iptables, SELinux/AppArmor concerns)?

If you confirm the interface names (LAN/WAN), NAT preference per-profile (or single global choice), IPv6 assignment method, and whether LAN-initiated connections should be allowed, I will generate:

full wg0..wg7 server .conf files and one client example file per profile with placeholders for keys,

an idempotent shell snippet to create the required iptables-legacy/ip6tables-legacy FORWARD and POSTROUTING rules per interface,

IPv6 routing/RA steps to enable global-prefix routing for clients and checks to validate v6 pathing,

verification and cleanup commands (including the delete-by-number and duplicate-removal script adapted to both IPv4 and IPv6).

When you confirm the missing choices above I’ll produce the concrete configs and idempotent commands.

