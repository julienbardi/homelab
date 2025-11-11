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

```bash
git clone https://github.com/radvd-project/radvd.git
cd radvd
git checkout v2.20

./autogen.sh
./configure --prefix=/usr/local --sysconfdir=/etc --mandir=/usr/share/man
make
sudo make install
```
This will place the new binary in `/usr/local/sbin/radvd`.

