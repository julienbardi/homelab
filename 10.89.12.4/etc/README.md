
## Conventions

### 🔑 Convention
Use fd10:8912:0:XX::/64 where XX is the subnet ID matching the WireGuard interface number.

🔑 wg0–wg7 mapping (8912 convention)
Interface	Subnet (ULA)	NAS address     	Firewall (UDP port)	Notes
wg0	fd10:8912:0:10::/64	fd10:8912:0:10::1	51420	Advertises DNS (::1) in radvd
wg1	fd10:8912:0:11::/64	fd10:8912:0:11::1	51421	You already set this one
wg2	fd10:8912:0:12::/64	fd10:8912:0:12::1	51422	Assign next port sequentially
wg3	fd10:8912:0:13::/64	fd10:8912:0:13::1	51423	
wg4	fd10:8912:0:14::/64	fd10:8912:0:14::1	51424	
wg5	fd10:8912:0:15::/64	fd10:8912:0:15::1	51425	
wg6	fd10:8912:0:16::/64	fd10:8912:0:16::1	51426	
wg7	fd10:8912:0:17::/64	fd10:8912:0:17::1	51427	Replace any old fd10:7:: rules


#### NAS: Network>Network Connection>Network Bridging

BR-LAN1 edit
Under IPv6, full the NAS UI
IPv6 address: fd10:8912:0:0::4/64
Default gateway (UI requirement): fd10:8912:0:0::1 (arbitrary, just needs to be in the same /64)
Preferred DNS: whichever NAS address you bind your resolver to (fd10:8912:0:0::4 or ::1)
⚡ Important note
The “default gateway” you enter in the NAS UI is not the real upstream gateway. It’s just a placeholder to satisfy the UI.

The real connectivity to the router/ISP is handled by ndppd, which makes the NAS answer neighbor discovery for those ULA addresses and forward traffic upstream.


#### a) Firewall on NAS
Write rules using these exact /64 prefixes.

Example: allow UDP forwarding for fd10:8912:0:17::/64 instead of fd10:7::/64.

This ensures packets match what radvd and WireGuard are actually advertising.

b) radvd.conf
Already correct in your working config: each interface wgX { … } block advertises the matching fd10:8912:0:XX::/64.

Keep bridge0 on fd10:8912:0:0::/64.

c) wg0.conf – wg7.conf
Assign each peer an address inside the matching subnet.

Example for wg7 peer:

ini
[Interface]
Address = fd10:8912:0:17::2/64
The NAS itself can use ::1 in each subnet (e.g. fd10:8912:0:17::1).

d) NAS network bridge properties
For bridge0, assign the NAS a stable address like:

Code
fd10:8912:0:0::1/64
That’s the address you already advertise as DNS in radvd.

Keep the global IPv6 and IPv4 addresses as they are; this ULA is just your internal namespace.

✅ Summary
Firewall: match fd10:8912:0:XX::/64.

radvd.conf: already aligned with fd10:8912:0:XX::/64.

wgX.conf: assign NAS ::1, peers ::2, ::3, etc. inside the correct subnet.

bridge0: NAS = fd10:8912:0:0::1/64.

This way, everything — firewall, radvd, WireGuard configs, and bridge properties — uses the same fd10:8912 namespace.


### NOTE USED: this would require also ndppd if I understood correctly

Addressing and ports table (finalized)
Interface	IPv4 subnet	IPv4 client dynamic range	IPv6 prefix (shared)	IPv6 client allocation range	WireGuard port
wg0	10.0.0.0/24	10.0.0.100 – 10.0.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::100 – ::1FF	51820
wg1	10.1.0.0/24	10.1.0.100 – 10.1.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::200 – ::2FF	51821
wg2	10.2.0.0/24	10.2.0.100 – 10.2.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::300 – ::3FF	51822
wg3	10.3.0.0/24	10.3.0.100 – 10.3.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::400 – ::4FF	51823
wg4	10.4.0.0/24	10.4.0.100 – 10.4.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::500 – ::5FF	51824
wg5	10.5.0.0/24	10.5.0.100 – 10.5.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::600 – ::6FF	51825
wg6	10.6.0.0/24	10.6.0.100 – 10.6.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::700 – ::7FF	51826
wg7	10.7.0.0/24	10.7.0.100 – 10.7.0.199	2a01:8b81:4800:9c00::/64	2a01:8b81:4800:9c00::800 – ::8FF	51827
Hint (identical settings for all interfaces)

Shared global IPv6 prefix: 2a01:8b81:4800:9c00::/64 (server uses ::1; infra reserved ::2–::ff).

Client IPv6 assignment: each client receives a /128 inside the shared /64; use the ranges above per wgN.

IPv4 reservation rule: .1 reserved for server/gateway, .2–.10 reserved for infra/management, clients assigned from .100–.199.

AllowedIPs format on server peers: use IPv4/32, IPv6/128 (example: 10.3.0.100/32, 2a01:8b81:4800:9c00::400/128).

Endpoint (public): bardi.ch — the WireGuard port for each interface must be forwarded on the ASUS router to the NAS (10.89.12.4) for the corresponding port shown in the table. Forward UDP ports 51820–51827 to 10.89.12.4 so external clients can reach the correct wg interface.


## Step 5: Build and install radvd 2.20


Now you can fetch and build the latest release:
Install GNU autotools packages
sudo apt install autoconf automake libtool pkg-config m4 libbsd-dev bison flex
```bash
mkdir -p /home/julie/src
cd /home/julie/src
git clone https://github.com/radvd-project/radvd.git
cd radvd
git tag -l
git checkout v2.20

./autogen.sh
./configure --prefix=/usr/local --sysconfdir=/etc --mandir=/usr/share/man
make
sudo make install
```
This will place the new binary in `/usr/local/sbin/radvd`.

Output of `./configure --prefix=/usr/local --sysconfdir=/etc --mandir=/usr/share/man`
Your build configuration:

        CPPFLAGS =
        CFLAGS = -g -O2
        LDFLAGS =
        Arch = linux
        Extras: privsep-linux.o device-linux.o netlink.o
        prefix: /usr/local
        PID file: /var/run/radvd.pid
        Log file: /var/log/radvd.log
        Config file: /etc/radvd.conf
        Radvd version: 2.20

/usr/local/sbin/radvd --version

IPv6 requires a link‑local address on every interface.

How to fix
Enable IPv6 on the bridge interface Make sure IPv6 is enabled in sysctl:

bash
sudo sysctl -w net.ipv6.conf.bridge0.disable_ipv6=0
To make it permanent, add to /etc/sysctl.conf:

Code
net.ipv6.conf.bridge0.disable_ipv6=0
Assign a link‑local address manually (optional) Normally the kernel auto‑assigns a link‑local when IPv6 is enabled. If not, you can add one:

bash
sudo ip -6 addr add fe80::1/64 dev bridge0
Verify Check addresses:

bash
ip -6 addr show dev bridge0
You should see a fe80::... entry.

Restart radvd Once the link‑local is present, restart radvd:

bash
sudo systemctl restart radvd
or if you’re running manually:

bash
sudo /usr/local/sbin/radvd -C /etc/radvd.conf -d 5 -n
⚡ Confirm advertisements
After radvd is running with a link‑local:

bash
sudo tcpdump -i bridge0 icmp6 and ip6[40] == 134
You should see ICMPv6 Router Advertisements being sent. Or use:

bash
rdisc6 bridge0
to query the RA directly.

