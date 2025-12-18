# Homelab Gateway Stack

## LAN topology 

LAN subnet IPv4: `10.89.12.0/24`
LAN subnet IPv6: `2a01:8b81:4800:9c00::/64`

## first setup

After a hard reset of UGOS DXP 4800+ nas, UGOS is configured as follows:
- Outbound UDP: rate‑limited, then dropped → DNS queries fail.
- ICMP echo (ping): dropped after a small burst → you can’t monitor reachability.
- Inbound SSH: restricted to RFC1918 ranges (10.0.0.0/8, 192.168.0.0/16, 172.16.0.0/12) → secure, but IPv6 SSH is dropped.
- Forwarding: only RELATED,ESTABLISHED → no new outbound connections allowed unless explicitly permitted.

🛠️ Minimal rules to add for basic connectivity
    ```
    📝 firewall-allow.sh
    sh
    #!/bin/sh
    # Add LAN-only ICMP echo rules and allow outbound DNS/HTTP/HTTPS/NTP
    # Includes rate-limited logging for dropped packets
    # Supports dry-run mode: run with ./firewall-allow.sh --dry-run
    # Footer shows Git commit hash if available, else file hash
    # Logs deployment to syslog for auditability
    
    DRYRUN=0
    [ "$1" = "--dry-run" ] && DRYRUN=1
    
    run() {
        if [ "$DRYRUN" -eq 1 ]; then
            echo "DRY-RUN: $*"
        else
            echo "Running: $*"
            $*
        fi
    }
    
    # IPv4: allow ping from LAN
    run nft add rule ip filter INPUT ip saddr 10.89.12.0/24 icmp type echo-request accept
    
    # IPv6: allow ping from LAN
    run nft add rule ip6 filter INPUT ip6 saddr 2a01:8b81:4800:9c00::/64 icmpv6 type echo-request accept
    
    # IPv4: allow outbound DNS
    run nft add rule ip filter OUTPUT udp dport 53 accept
    run nft add rule ip filter OUTPUT tcp dport 53 accept
    
    # IPv6: allow outbound DNS
    run nft add rule ip6 filter OUTPUT udp dport 53 accept
    run nft add rule ip6 filter OUTPUT tcp dport 53 accept
    
    # IPv4: allow outbound web traffic
    run nft add rule ip filter OUTPUT tcp dport 80 accept
    run nft add rule ip filter OUTPUT tcp dport 443 accept
    
    # IPv6: allow outbound web traffic
    run nft add rule ip6 filter OUTPUT tcp dport 80 accept
    run nft add rule ip6 filter OUTPUT tcp dport 443 accept
    
    # Optional: allow outbound ICMP for diagnostics
    run nft add rule ip filter OUTPUT icmp type echo-request accept
    run nft add rule ip6 filter OUTPUT icmpv6 type echo-request accept
    
    # Optional: allow outbound NTP
    run nft add rule ip filter OUTPUT udp dport 123 accept
    run nft add rule ip6 filter OUTPUT udp dport 123 accept
    
    # Rate-limited logging of drops (safe against DoS floods)
    run nft add rule ip filter INPUT log prefix "DROP-IPv4: " level info limit rate 5/second
    run nft add rule ip6 filter INPUT log prefix "DROP-IPv6: " level info limit rate 5/second
    
    # Footer: Git commit hash if available, else file hash
    if command -v git >/dev/null 2>&1 && git rev-parse --short HEAD >/dev/null 2>&1; then
        VERSION="commit $(git rev-parse --short HEAD)"
    else
        VERSION="hash $(sha256sum "$0" | cut -c1-8)"
    fi
    
    MESSAGE="✅ Firewall rules applied ($VERSION) at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Echo to shell
    echo "$MESSAGE"
    
    # Log to syslog
    logger -t firewall-allow "$MESSAGE"
🔹 Usage
Dry run (preview only):
    ```bash
    ./firewall-allow.sh --dry-run
Apply rules:
    ```bash
    sudo ./firewall-allow.sh
✅ Result
- LAN‑only ping allowed
- Outbound DNS, web, ICMP, NTP allowed
- Drop logging rate‑limited to avoid DoS risk
- Footer shows Git commit hash (or file hash fallback)
- Deployment recorded in syslog (journalctl -t firewall-allow)
- 
5. Verify
List the rules back:
    ```bash
    sudo nft list ruleset | grep dport

6. Persist changes
On Debian 12 with UGOS:
    ```bash
    sudo sh -c 'nft list ruleset > /etc/nftables.conf'
    sudo systemctl restart nftables
This ensures your additions survive reboot and remain layered on top of UGOS defaults.



## Overview
This repository contains a modular, audit‑friendly homelab stack built in **generations**:

- **Gen0** → foundational services (Headscale, CoreDNS, Unbound, firewall, audit)
- **Gen1** → helpers (Caddy reload, tailnet management, trust anchor rotation, WireGuard baseline)
- **Gen2** → deployment artifact (site landing page)
- **Supporting scripts** → subnet router logic, aliases, systemd unit
- **Config templates** → Headscale, CoreDNS, Unbound

The design principle is **minimal, explicit, reproducible**. Every script logs degraded mode if a step fails, so you always know what state the system is in.

---

## Repository Layout

```
/home/julie/src/homelab
│
├── Makefile                 # Orchestration entrypoint (Gen0 → Gen2)
├── .gitignore               # Hygiene rules (Gen0 check)
├── README.md                # Repo policy, usage, resilience notes
│
├── gen0/                    # Foundational scripts
│   ├── setup_headscale.sh
│   ├── setup_coredns.sh
│   ├── dns_setup.sh
│   ├── wg_firewall_apply.sh
│   └── router_audit.sh
│
├── gen1/                    # Dependent helpers
│   ├── caddy-reload.sh
│   ├── tailnet.sh
│   ├── rotate-unbound-rootkeys.sh
│   └── wg_baseline.sh
│
├── gen2/                    # Final deployment artifacts
│   └── site/
│       └── index.html
│
├── config/                  # Static config templates
│   ├── headscale.yaml       # main Headscale config (no inline derp_map)
│   ├── derp.yaml            # external DERPMap file in map[int]*tailcfg.DERPRegion format
│   ├── coredns/Corefile
│   └── unbound/unbound.conf.template
│
├── systemd/                 # Unit templates (not deployed copies)
│   ├── headscale.service
│   ├── coredns.service
│   └── subnet-router.service
│
└── scripts/                 # Supporting utilities
    ├── setup-subnet-router.sh
    └── aliases.sh           # router-logs, router-deploy
```

## Homelab Dependency Graph
```
all
 ├── gen0
 │    ├── headscale
 │    │    ├── setup_headscale.sh
 │    │    └── noise-key generation (/etc/headscale/noise_private.key)
 │    ├── coredns
 │    │    └── setup_coredns.sh
 │    ├── dns
 │    │    └── dns_setup.sh
 │    ├── firewall
 │    │    └── wg_firewall_apply.sh
 │    └── audit
 │         └── router_audit.sh
 │
 ├── gen1
 │    ├── caddy
 │    │    └── caddy-reload.sh
 │    ├── tailnet
 │    │    └── tailnet.sh
 │    ├── rotate
 │    │    └── rotate-unbound-rootkeys.sh
 │    └── wg-baseline
 │         └── wg_baseline.sh
 │
 └── gen2
      └── site
           └── index.html
```

---


## Usage

### Orchestration
Run the full stack:

```bash
make all
```
Run a specific generation:

```
make gen0
make gen1
make gen2
```

Linting
Check all scripts for syntax errors:
```
make lint
```
Cleaning
Remove generated artifacts (keys, configs, QR codes):

```
make clean
```

Supporting Scripts
setup-subnet-router.sh → subnet router logic with conflict detection, NAT, dnsmasq restart, GRO tuning, version auto‑increment, footer logging.

aliases.sh → operational shortcuts:

router-logs → tail live logs of subnet-router.service

router-deploy → copy updated script and restart service

subnet-router.service → systemd unit to run router script at boot and log version line.

Config Templates
headscale.yaml → Headscale server + DNS integration

coredns/Corefile → CoreDNS plugin for tailnet resolution, forwards to Unbound

unbound.conf.template → Unbound baseline with DNSSEC trust anchors

Resilience Notes
Degraded mode logging: every script logs failures without aborting the entire stack.

iptables‑legacy enforced: firewall scripts explicitly call iptables-legacy for deterministic behavior.

Versioning: subnet router script auto‑increments version and logs timestamp at deploy.

Auditability: all logs go to both file and syslog, so you can grep across services.

Collaborator Policy
Keep changes minimal and explicit.

Always document .PHONY targets in the Makefile.

Never trust source IP alone — scope firewall rules to interfaces.

Validate configs before reload (Caddy, Unbound).

Use router-deploy alias for safe updates.

Next Steps
Extend site/index.html into a dashboard (service health, logs).

Add regression tests for DNSSEC rotation.

Document rollback commands for each generation.


## DNS Architecture

- **Unbound**: Recursive resolver, DNSSEC validation, caching.
- **CoreDNS**: Authoritative for `tailnet.` domain, forwards other queries upstream.

### Flow
Client → CoreDNS → Unbound → Internet root/authoritative servers

### Notes
- CoreDNS does not require Unbound to run, but in this homelab Unbound is the upstream.
- Unbound listens on 10.89.12.4:53
- CoreDNS forwards non-tailnet queries to Unbound at 10.89.12.4:53







## Current Scripts

### `scripts/setup-subnet-router.sh`
Configures the NAS as a subnet router with:
- LAN subnet detection (excluding Docker conflicts)
- NAT and IP forwarding
- `dnsmasq` restart
- Tailscale route advertisement
- GRO tuning
- Logs to `/var/log/setup-subnet-router.log` with Git commit hash
- Auto‑creates and enables `setup-subnet-router.service`

Usage:
```bash
# Deploy
sudo cp scripts/setup-subnet-router.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/setup-subnet-router.sh
sudo setup-subnet-router.sh

# Remove service
sudo setup-subnet-router.sh --remove
````

## Repo Structure
 ```bash
homelab/
├── scripts/        # Automation scripts (currently only setup-subnet-router.sh)
├── .gitignore      # Ignore rules for logs, temp files, NAS sync dbs, etc.
└── README.md       # Project overview and usage
````

## 🖧 Network Topology and Performance Tests
This section documents the lab topology and the measured throughput between nodes using `iperf3`.  
Tests were run with 4 parallel streams (`-P 4`) and in both directions (`-R` for reverse mode).

### Machine Inventory

iperf3.exe -P 8 -R -c nas
|-------------|
| Source      | Destination |
|-------------|-------------|-----------
| omen30l     | nas         | 2.38 Gbps
| omen30l     | router      | 1.12 Gbps
| omen30l     | diskstation | 0.95 Gbps
| router      | nas         | 2.26 Gbps
| router      | diskstation | 0.94 Gbps


Linux: iperf3 -P 8 -R -c ping.online.net           Windows: iperf3.exe -P 8 -R -c ping.online.net

| Machine     | IPv4 Address | IPv6 Address        | Notes                  | iperf3 -P 8 -R -c ping.online.net |
|-------------|--------------|---------------------|------------------------|-----------------------------------|
| omen30l     | 10.89.12.123 |                     | Windows host, 10 GbE   | 197-209 Mbps |
| nas         | 10.89.12.4   |                     | 10 GbE capable storage | 601-645 Mbps |
| disksation  | 10.89.12.2   |                     | Synology, 1 GbE        | 500-530 Mbps |
| router      | 10.89.12.1   |                     | Asus router, 1 GbE     | 605-643 Mpbs |
| s22         |              |                     |                        |

### 🖧 Network Topology and Performance Tests
Throughput was measured with `iperf3` using 4 parallel streams over 10 seconds.
- Destination (server):
  ```bash601-
  iperf3 -s 
  ip -4 addr show scope global | awk '/inet / {print $2}' | head -n1 | cut -d/ -f1
  iperf3 -s -6 
  ip -6 addr show scope global | awk '/inet / {print $2}' | head -n1 | cut -d/ -f1
  
  # show IPv6 address 
  ip -6 addr show scope global | awk '/inet6/ && $2 !~ /^fd/ {print $2}' | head -n1 | cut -d/ -f1 # to get <IPv6_address>
  
- Source (client):
  ```bash
  iperf3 -P 4 -t 10 -R    -c <IPv4_address>
  iperf3 -P 4 -t 10 -R -6 -c <IPv6_address>
### IPv4 vs IPv6 iperf3 Results
| Source ↔ Destination       | IPv4 Throughput (Gbps) (v4/v6) | Retransmits (v4/v6) | Notes                                                                 | Health |
|----------------------------|--------------------------------|---------------------|-----------------------------------------------------------------------|--------|
| omen30l ↔ nas              | 9.40 / 10.5                   | 0 / 0               | Excellent 10 GbE path, fully saturating line‑rate                      | ✅ Good |
| omen30l ↔ disksation       | 1.1                           | 0                   | Endpoint CPU/disk bottleneck, not the network                          | ⚠️ Fair |
| omen30l ↔ router br0       | 1.10 / 1.10                   | 176 / 235           | Gigabit link saturated, retransmits indicate congestion/noise          | ⚠️ Fair |
| omen30l ↔ router eth0      | 0.50                          | 5                   | WAN interface, ~500 Mb/s, stable with minimal loss                     | ✅ Good |
| omen30l ↔ router tailscale0| 0.48                          | 2                   | Tailscale overlay, ~500 Mb/s, very low retransmits                     | ✅ Good |
| disksation ↔ QNAP          |                               |                     | CPU bottleneck on NAS/QNAP, throughput limited by hardware             | ❌ Poor |
| s22 ↔ router br0           | 0.83                          | 1940                | WLAN path, decent throughput but very high retransmits (Wi‑Fi noise)   | ⚠️ Fair |
| s22 ↔ router bardi.ch      | 0.90                          | 287                 | WLAN path, good throughput, moderate retransmits                       | ✅ Good |
| s22 ↔ disksation           | 0.89                          | 0                   | WLAN path, stable and clean                                            | ✅ Good |
| s22 ↔ nas                  | 1.01                          | 517                 | WLAN path, powered device, some retransmits                            | ⚠️ Fair |
| s22 ↔ nas                  | 0.013 →, 0.09 ←               | 0                   | WLAN + WireGuard via router, extremely poor (router CPU/MTU overhead)  | ❌ Poor |
| s22 ↔ nas                  | 0.006 →, 0.03 ←               | 0                   | 4G + WireGuard via router, extremely poor (mobile uplink + WG overhead)| ❌ Poor |

### iperf3 -P 8 -R -c ping.online.net




### Notes
- **Arrows:** → forward, ← reverse, ↔ both directions.  
- **Asymmetry:** When results differ, values are summarized in the Summary colum

---

## ✅ Next Step

1. Create the file in your repo root:
   ```bash
   cd ~/homelab
   nano README.md
   ````

## sudo apt

sudo apt update
sudo apt install -y shellcheck

## Core DNS (experimental)

We use CorDNS to provide DOH for our DNS

Quick (recommended): install prebuilt binary
Download and install the latest prebuilt binary:

```
sudo curl -L -o /usr/local/bin/coredns \
  "https://github.com/coredns/coredns/releases/latest/download/coredns_amd64"
sudo chmod 0755 /usr/local/bin/coredns
sudo mkdir -p /etc/coredns
```

Verify binary and plugins:

```
/usr/local/bin/coredns -version
/usr/local/bin/coredns -plugins
```
If the doh plugin appears in -plugins you’re good for DoH without compiling.

Compile CoreDNS on Debian 12 (when you need custom plugins)
Prerequisites

Debian 12, internet access, a user with sudo.

Go toolchain (use Go 1.20+; match project recommendations).

Install Go and build tools:

```
sudo apt update
sudo apt install -y git build-essential


# Install Go from Debian repos (may be older) or the official tarball. Example: official tarball install
GO_VER=1.21.2
wget -q https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VER}.linux-amd64.tar.gz
rm go${GO_VER}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
export PATH=$PATH:/usr/local/go/bin
```

Clone CoreDNS:

```
git clone https://github.com/coredns/coredns.git
cd coredns
# Optionally check out a release tag:
git fetch --tags
git checkout v1.11.0   # replace with desired release tag
```
Build the default CoreDNS binary:

```
make

# produced binary: ./coredns
```
Build with a specific plugin set (optional)

To include or exclude plugins, set COREDNS_PLUGINS:

```
# example: build with doh, forward, cache explicitly
COREDNS_PLUGINS="doh forward cache log errors" make
```
After building, verify plugins:

```
./coredns -plugins
```

Install the binary system-wide:

```
sudo cp coredns /usr/local/bin/coredns
sudo chmod 0755 /usr/local/bin/coredns
```
Basic run/test (non-root port to test quickly):

```
./coredns -dns.port=1053 &
dig @127.0.0.1 -p 1053 example.com
```


permission set on 2025-11-16
sudo useradd -r -s /usr/sbin/nologin coredns || true
sudo mkdir -p /etc/coredns
sudo chown root:coredns /etc/coredns
sudo chmod 750 /etc/coredns
sudo chown root:coredns /etc/coredns/Corefile
sudo chmod 640 /etc/coredns/Corefile


## Editor settings

This project requires **literal tabs** in Makefiles (`Makefile`, `.mk` includes).
To enforce this, we provide a workspace settings file:

- Copy `.vscode/settings.json` into your repo (already included).
- When you open the repo in VS Code, these settings are applied automatically.
- Do not override with spaces — GNU Make requires tabs in recipe lines.

If you use another editor, configure it to insert tabs instead of spaces for Makefiles.


# Setup tailscale on my phone:
##🖥️ On the NAS (prepare QR key and advertise exit node)

### Generate a preauth key and display it as a QR code (single line):

```bash
headscale preauthkeys create --user bardi-family --ephemeral=false --reusable=false --output json | jq -r '.key' | qrencode -t ANSIUTF8
```
- This prints a QR code directly in your terminal.
- Keep this terminal open — you’ll scan it with your phone.

### Optional check:

Run
```
( sudo sysctl net.ipv4.ip_forward | grep -q "1" && v4f="IPv4FWD✅" || v4f="IPv4FWD❌" ; \
  sudo sysctl net.ipv6.conf.all.forwarding | grep -q "1" && v6f="IPv6FWD✅" || v6f="IPv6FWD❌" ; \
  sudo iptables-legacy -t nat -L POSTROUTING -n -v | grep -q "MASQUERADE.*10.89.12.0/24" && v4lan="IPv4LAN✅" || v4lan="IPv4LAN❌" ; \
  sudo iptables-legacy -t nat -L POSTROUTING -n -v | grep -q "MASQUERADE.*100.64.0.0/10" && v4ts="IPv4TS✅" || v4ts="IPv4TS❌" ; \
  sudo ip6tables-legacy -t nat -L POSTROUTING -n -v | grep -q "MASQUERADE.*fd7a:115c:a1e0::/48" && v6ts="IPv6TS✅" || v6ts="IPv6TS❌" ; \
  sudo iptables-legacy -L FORWARD -n -v | grep -q "tailscale0.*100.64.0.0/10" && fwd4="FWDv4✅" || fwd4="FWDv4❌" ; \
  sudo ip6tables-legacy -L FORWARD -n -v | grep -q "tailscale0.*fd7a:115c:a1e0::/48" && fwd6="FWDv6✅" || fwd6="FWDv6❌" ; \
  if [[ $v4f == *✅ && $v6f == *✅ && $v4lan == *✅ && $v4ts == *✅ && $v6ts == *✅ && $fwd4 == *✅ && $fwd6 == *✅ ]]; then overall="✅ OK"; else overall="❌ FAIL"; fi ; \
  echo "$overall Exit-node checks: $v4f $v6f $v4lan $v4ts $v6ts $fwd4 $fwd6" )
```

or inspect manually
```bash
sudo sysctl net.ipv4.ip_forward && \
sudo sysctl net.ipv6.conf.all.forwarding && \
sudo iptables-legacy -t nat -L POSTROUTING -n -v && \
sudo ip6tables-legacy -t nat -L POSTROUTING -n -v && \
sudo iptables-legacy -L FORWARD -n -v && \
sudo ip6tables-legacy -L FORWARD -n -v
```
- Expected both should be 1 for the first two command
- Ensure MASQUERADE rules exist for 100.64.0.0/10 and fd7a:115c:a1e0::/48.
- Ensure ACCEPT rules exist for tailscale0.
-> if not ok, run `make tailscaled`

## 📱 On your phone (Tailscale app)

1. Install the Tailscale app:
- Android → open Google Play Store, search for Tailscale, tap Install.
- iOS → open App Store, search for Tailscale, tap Get.

2. Open the Tailscale app.

3. Enroll using the QR key:
- Tap Log in.
- Tap the ⋮ (three dots) menu in the top‑right corner.
- Tap Use auth key.
- Tap Scan QR code.
- Switch to your camera app, point your phone’s camera at the QR code displayed in your NAS terminal, copy the code, switch back to tailscale and paste the code into the field use auth key
- Wait until the app shows “Connected” with a 100.64.x.x address.

4. Select NAS as exit node:
- In the app, tap Settings (gear icon).
- Tap Exit Node.
- A list of available exit nodes appears — select your NAS.
- Status should now show Using exit node.

5. Enable tailnet DNS:
- In Settings, tap DNS.
- Toggle Use tailnet DNS to On.
- Confirm that the advertised DNS server (from your NAS) is listed.

## ✅ Verification (on the phone)

1. Ping NAS LAN IP:
- In the app → Machines → tap NAS → tap Ping.
- Should succeed.

2. Test internet connectivity:
- Open a browser → visit https://example.com.
- Page should load.

3. Optional CLI checks (Termux on Android):
```
pkg update && pkg install -y tailscale
tailscale status
tailscale ping 10.89.12.4
tailscale ping 8.8.8.8
nslookup example.com
curl https://example.com
```
