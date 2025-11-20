# Homelab Gateway Stack

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
│   ├── headscale.yaml
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


## Headscale 0.27 (broken)

### Install version 0.27

sudo systemctl stop headscale.service && \
wget -O /usr/local/bin/headscale https://github.com/juanfont/headscale/releases/download/v0.27.0/headscale_0.27.0_linux_amd64 && \
sudo chmod +x /usr/local/bin/headscale && \
sudo systemctl start headscale.service

/usr/local/bin/headscale version


sudo vi /etc/systemd/system/headscale.service
# autogenerated by /home/julie/homelab/scripts/setup-homelab.sh since v0.82, MODIFIED
# source: $HEADSCALE_UNIT_CONTENT
# DO NOT EDIT — changes will be overwritten
[Unit]
Description=Headscale coordination server
After=network.target

[Service]
ExecStart=
ExecStart=/usr/local/bin/headscale serve --config /etc/headscale/config.yaml
Restart=always

[Install]
WantedBy=multi-user.target

<EOF


On NAS
sudo systemctl daemon-reload
sudo systemctl restart headscale.service

check
sudo journalctl -u headscale.service -f


### configure


sudo headscale namespaces create homelab
sudo headscale namespaces list

v0.26.1

sudo headscale users create homelab


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
