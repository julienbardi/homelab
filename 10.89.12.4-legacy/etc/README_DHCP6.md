# DHCP6
## Introduction

Unbound is a recursive DNS resolver. It answers queries, caches results, and can serve your LAN.
It does not hand out DNS server addresses to clients. That’s the job of either:
- Router Advertisements (RA) with RDNSS (which Windows ignores), or
- DHCPv6, which Windows does honor for DNS.

So if you want Windows clients to automatically pick up fd10:8912:0:0::1 (your Unbound instance) as their DNS, you need a DHCPv6 server running alongside Unbound. Unbound itself doesn’t advertise DNS addresses.

## ✅ How to install it
On Debian/Ubuntu systems, the package is called isc-dhcp-server (it includes both IPv4 and IPv6 daemons):

bash
sudo apt update
sudo apt install isc-dhcp-server
After installation you’ll have two units available:

isc-dhcp-server.service (IPv4)

isc-dhcp-server6.service (IPv6)

Then you can enable the IPv6 one:

bash
sudo systemctl enable isc-dhcp-server6
sudo systemctl start isc-dhcp-server6

## 🛠 Minimal DHCPv6 setup (with isc-dhcp-server)
Here’s a simple config snippet that only hands out DNS, leaving addresses to SLAAC/radvd:

`sudoedit /etc/dhcp/dhcpd6.conf`:

```
conf
option dhcp6.name-servers fd10:8912:0:0::1, 2a01:8b81:4800:9c00::1;

subnet6 fd10:8912:0:0::/64 {
    # no address pools, SLAAC handles addresses
}
```
This way:
- radvd continues to advertise prefixes and gateways (SLAAC).
- DHCPv6 only hands out DNS servers, which Windows will honor

- option dhcp6.name-servers → tells Windows to use your Unbound (fd10:8912:0:0::1) and ISP DNS as fallback.
- subnet6 block is required, but you don’t need to hand out addresses if SLAAC is already working.

Enable and start:
```bash
sudo systemctl enable isc-dhcp-server6
sudo systemctl start isc-dhcp-server6
```

## ✅ Steps to fix
Stop the IPv4 service (you don’t need it):

bash
sudo systemctl disable isc-dhcp-server
sudo systemctl stop isc-dhcp-server
Create the IPv6 config file `sudoedit /etc/dhcp/dhcpd6.conf`:

conf
option dhcp6.name-servers fd10:8912:0:0::1, 2a01:8b81:4800:9c00::1;

subnet6 fd10:8912:0:0::/64 {
    # no address pools, SLAAC handles addresses
    # Even if you don’t want DHCPv6 handing out addresses, ISC DHCP often won’t reply unless a range6 is defined.
    range6 fd10:8912:0:0::100 fd10:8912:0:0::200;
}
This tells Windows clients to use your Unbound (fd10:8912:0:0::1) and ISP DNS as fallback.

Bind DHCPv6 to the right interface Edit `sudoedit /etc/default/isc-dhcp-server` and set:

```
INTERFACESv6="bridge0"
INTERFACES=""
```
(replace with the interface you want DHCPv6 to listen on).

Enable and start the IPv6 service:

```
sudo systemctl enable isc-dhcp-server6
sudo systemctl start isc-dhcp-server6
sudo systemctl status isc-dhcp-server6
```

```
sudo systemctl restart isc-dhcp-server
sudo systemctl status isc-dhcp-server6
sudo journalctl -u isc-dhcp-server -f
```