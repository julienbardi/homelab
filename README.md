# Homelab Gateway Stack

## LAN topology
This system uses a dual‑LAN design with clearly separated roles to ensure deterministic routing, high performance, and clean firewall behavior.

Routed LAN (LAN2 – Router‑connected)
- IPv4 subnet: `10.89.12.0/24`
- IPv6 subnet: `2a01:8b81:4800:9c00::/64`
- Purpose: Internet access, routed LAN traffic, VPN egress
- Gateway: `10.89.12.1`
- IPv6: Fully routed via router (RA + default gateway)
This interface is the **only default route** for the system. All outbound traffic (updates, package installs, VPN traffic) must exit via this LAN.

Direct‑attach LAN (LAN1 – 10 Gbps point‑to‑point)
LAN1 is a **static, IPv4‑only, point‑to‑point link** used exclusively for high‑speed local access (storage, management, bulk transfers).
- Link type: Direct PC ↔ NAS (10 Gbps)
- IPv4 subnet: `10.89.13.0/24`
- IPv6: Disabled
- Gateway: None
- DNS: None
There is:
- No router
- No DHCP
- No IPv6 routing
- No NAT
Both ends **must be manually configured**.
This design avoids ARP ambiguity, asymmetric routing issues, and IPv6 link‑local delays, and behaves like a dedicated storage fabric.

## Design notes
- LAN1 and LAN2 are intentionally not bridged
- Each interface has a single, well‑defined role
- Asymmetric routing is expected and explicitly allowed at the kernel level
- Firewall rules are interface‑aware

## DXP4800+ first setup

The initial setup of the DXP4800+ assumes the LAN topology described above and must be completed in the following order:
1. Configure LAN2 (router‑connected) with a static IPv4 address and default gateway
2. Verify internet connectivity and system updates
3. Configure LAN1 (10 Gbps) with a static IPv4 address and no gateway
4. Apply required kernel networking settings (rp_filter, ARP behavior)
5. Apply firewall rules with explicit interface separation
This order ensures reliable access during setup and prevents silent connectivity failures caused by asymmetric routing or incomplete firewall rules.

### 1. Establish initial SSH access and internet connectivity
UGOS manages its own firewall and does not allow SSH on custom ports by default.
To establish connectivity during first setup, SSH must be explicitly allowed.

On the NAS:
```
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
vi ~/.ssh/authorized_keys
add content as any line of "code C:\Users\julie\.ssh\id_ed25519.pub"
```
These permissions are mandatory — SSH will silently ignore the file if they’re wrong.

From your PC, copy the contents of:
~/.ssh/id_ed25519.pub
Then on the NAS:
```
nano ~/.ssh/authorized_keys
```
Paste the entire line (one key per line), save, exit.

Verify it works
From the PC:

```powershell
ssh -p2222 julie@10.89.13.4
```
You should connect without a password prompt.

#### Allow SSH via LAN2 (router‑connected) and LAN1 (PC connected)

UGOS does not support persistent nftables.conf in the usual Debian way.
The safest method is to re‑apply your rules at boot via a startup script.

Note: On UGOS, SSH typically listens on port 2222 only. Port 22 may be closed or unused depending on firmware. Both ports are allowed in firewall rules to avoid lockout during upgrades, but only port 2222 is expected to accept connections.

#### 1 Create a firewall restore script
bash
sudo nano /usr/local/bin/ug-firewall-override.sh
Paste this:

```bash
#!/bin/sh
# UGOS firewall SSH override
# Applied after UG firewall initialization

nft add rule ip filter UG_INPUT iifname "eth1" tcp dport 22 accept
nft add rule ip filter UG_INPUT iifname "eth1" tcp dport 2222 accept
#allow SSH via LAN1 (10 Gbps direct link)
nft add rule ip filter UG_INPUT iifname "eth0" tcp dport 22 accept
nft add rule ip filter UG_INPUT iifname "eth0" tcp dport 2222 accept
```
Save and exit.

#### 2 Make it executable
```bash
sudo chmod +x /usr/local/bin/ug-firewall-override.sh
```
#### 3 Create a systemd service
```bash
sudo nano /etc/systemd/system/ug-firewall-override.service
```

Paste
```bash
[Unit]
Description=UGOS firewall override (SSH rules)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ug-firewall-override.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

#### 4 Reload systemd and enable it
```bash
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable ug-firewall-override.service
```
#### 5 Test immediately (no reboot needed)
```bash
sudo systemctl start ug-firewall-override.service
sudo nft list chain ip filter UG_INPUT
```
You should see your SSH rules appear.
#### 6 Reboot to confirm persistence
```bash
# reboot in 1 minute
sudo shutdown -r +1 "Rebooting to validate persistent network configuration"
```
After reboot:
```bash
sudo sysctl net.ipv4.conf.eth0.rp_filter
sudo nft list chain ip filter UG_INPUT
```
Your rules will still be there.

🧠 Why this works on UGOS (and rc.local doesn't)
- UGOS regenerates nftables rules at boot, but does not overwrite custom systemd units

### 2. Apply required kernel networking settings

Because the NAS is multi‑homed, asymmetric routing must be explicitly allowed.

Persist sysctl settings via /etc/sysctl.d/
This is the correct Linux mechanism, and UGOS honors it.

1️⃣ Create a dedicated sysctl file
```bash
sudo nano /etc/sysctl.d/99-ug-multilan.conf
```
Paste:
```conf
# Allow asymmetric routing on multi-homed NAS
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.eth0.rp_filter = 2
net.ipv4.conf.eth1.rp_filter = 2

# Prevent ARP flux on dual-LAN setup
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
```
Save and exit.

2️⃣ Apply immediately (no reboot needed)
```bash
sudo sysctl --system
```
3️⃣ Verify persistence
```bash
sudo sysctl net.ipv4.conf.eth0.rp_filter
sudo sysctl net.ipv4.conf.eth1.rp_filter
sudo sysctl net.ipv4.conf.all.arp_ignore
```
Reboot once to confirm they survive.

These settings prevent silent packet drops and ARP confusion.

🧠 Why this is the right architecture
Component	Responsibility
| Component  | Responsibility |
|:-----------|:---------------|
|`/etc/sysctl.d/99-ug-multilan.conf`|	Kernel routing & ARP behavior|
|`/usr/local/bin/ug-firewall-override.sh`|	Interface‑aware firewall rules|
|`/etc/rc.local`|	Execution order glue: systemd oneshot service (After=network-online.target) |

Each layer does one thing well.
This is exactly how you’d structure it on a router, firewall appliance, or production NAS.


### 3. Configure SSH key‑based authentication
Where SSH keys live on the NAS
For user julie, public keys must be placed in:

```Code
/home/julie/.ssh/authorized_keys
```
Required permissions:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```
#### Important reminder
SSH key authentication must be tested from the client that owns the private key.  
Running ssh on the NAS itself will always fall back to password authentication.

The private key stays on the PC.
Only the public key is stored on the NAS.

### 4. Validation
From a LAN2 host (router LAN):

```powershell
ssh -p2222 julie@10.89.12.4
```
From the direct‑attached PC on LAN1:
```powershell
ssh -p2222 julie@10.89.13.4
```
Successful login should occur without a password prompt.

## Install git
### 1. Install git
```
sudo apt-get install git --no-upgrade
```
This ensures:
- Git is installed
- Only new packages are added
- No existing packages are upgraded
- UGOS‑frozen packages remain untouched
This is the safest possible command on a UGOS‑based system.
### 2. Add SSH public key of the nac and PC/laptop to gitlab as authorization and signing key
- On Linux: cat ~/.ssh/id_ed25519.pub
- On PC (PowerShell): type C:\Users\julie\.ssh\id_ed25519.pub
- Add each of the above key as authentication and then repeat as signing key on https://github.com/settings/keys
- At the bottom tick vigilant mode

### 3. clone the repository
```
cd ~/src/
git clone git@github.com:Jambo15/homelab.git
```

### 4. Set your global Git name and email
On nas:
```
cd ~/src/homelab
git config --global user.name "Jambo15"
git config --global user.email "Jambo15@users.noreply.github.com"
# Verify your global identity
git config --global user.name
git config --global user.email
```
```
# Rename the existing GitHub remote
git remote rename origin github
# verify
git remote -v


#add GitLab as your new primary remote
git remote add origin git@gitlab.com:jbardi/homelab.git
# verify the remotes
git remote -v

# Merge. This keeps both histories and simply merges the GitLab YAML commit into your repo.
git pull origin main --allow-unrelated-histories --no-rebase
git push origin main
git pull github main --allow-unrelated-histories --no-rebase
git push github main

#set GitLab as the upstream so that git push (without arguments) goes to the right place.
git branch --set-upstream-to=origin/main
```

From now on, I need to push as follows to keep both repo in sync
```
#Push to GitLab (primary)
git push;
#Mirror to GitHub
git push github main
```
🟢 Why this works so well
- Git treats each remote independently
- You avoid merge conflicts
- You stay in full control
- You can switch primary/secondary anytime
- You keep GitHub Copilot for commit messages
- You keep GitLab for infra, CI, and private hosting


## DO NOT USE AS THIS FAILS: VS Code Remote‑SSH on Ugreen DXP4800+ (Manual Server Install)
The Ugreen DXP4800+ runs a minimal BusyBox‑style Linux environment that cannot auto‑install the VS Code Server. To enable full Remote‑SSH support (Explorer tree, Git integration, remote terminal), the VS Code Server must be installed manually.

### Manual installation steps

#### 1. Determine your VS Code commit ID (on your PC)
Run:
code --version

Example:
1.107.1
994fd12f8d3a5aa16f17d42c041e5809167e845a
x64

Use the second line (the commit ID).

#### 2. Create the VS Code Server directory (on the NAS)
mkdir -p ~/.vscode-server/bin/994fd12f8d3a5aa16f17d42c041e5809167e845a

#### 3. Download the matching VS Code Server build
curl -L https://update.code.visualstudio.com/commit:994fd12f8d3a5aa16f17d42c041e5809167e845a/server-linux-x64/stable -o vscode-server.tar.gz

#### 4. Extract the server into the correct folder
tar -xzf vscode-server.tar.gz -C ~/.vscode-server/bin/994fd12f8d3a5aa16f17d42c041e5809167e845a --strip-components=1

#### 5. Clean up
rm vscode-server.tar.gz

#### 7. Reconnect from VS Code
Close all VS Code windows, reopen VS Code, click the green “<>” Remote indicator, choose “Connect to Host → nas”, then open the folder /home/julie/src/homelab. The Explorer tree, Git integration, and remote terminal will now work normally.


## Install code-server
On NAS
```
curl -fsSL https://code-server.dev/install.sh | sh
sudo systemctl enable --now code-server@$USER
```
vi  ~/.config/code-server/config.yaml
Temporary change: bind-addr: 0.0.0.0:8080 (not 127.0.0.1:8080)

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
Tests were run with 8 parallel streams (`-P 4`) and in both directions (`-R` for reverse mode).

### 🖧 Machine IP Overview (IPv4 + IPv6)
Code
| Host        | IPv4           | IPv6                                |
|-------------|----------------|-------------------------------------|
| omen30l     | via router     | via router                          |
| nas         | 10.89.12.4     | 2a01:8b81:4800:9c00::4              |
| router      | 10.89.12.1     | 2a01:8b81:4800:9c00::1              |
| diskstation | 10.89.12.2     | 2a01:8b81:4800:9c00::2              |
| s22         | DHCP (varies)  | SLAAC (varies)                      |
| s22 WG      | via router WG  | via router WG                       |
| s22 4G WG   | via router WG  | via router WG                       |

### 🖧 Performance Tests
on destination: iperf3 -s
on source: 
- iperf3.exe    -P 8 -R -c 10.89.13.4
- iperf3.exe -6 -P 8 -R -c 2a01:8b81:4800:9c00::5
The lowest value between seneder ans receiver is reported

| Source      | Destination   | Iface | IPv4 (Mb/s) | IPv6 (Mb/s) | Health             |
|-------------|---------------|-------|-------------|-------------|--------------------|
| omen30l     | nas           | LAN   | 9360        | 8830        | ✅ 10G  ██████████ |
| nas         | router        | LAN   | 2140        | 1760        | ✅ 2.5G ██         |
| omen30l     | router        | LAN   |  942        |  925        | ✅ 1G   █          |
| omen30l     | diskstation   | LAN   |  949        |  938        | ✅ 1G   █          |
| nas         | diskstation   | LAN   |  941        |  909        | ✅ 1G   █          |
| omen30l     | init7         | WAN   |  505        |     —       | ✅ 1G   █          |
| omen30l     | t5.cscs.ch    | WAN   |  504        |     —       | ✅ 1G   █          |
| s22         | nas           | LAN   |  596        |  617        | ✅ 1G   █          |
| s22         | diskstation   | LAN   |  685        |  611        | ✅ 1G   █          |
| s22         | nas           | WGr   |    1        |    2        | ⚠️ 1M   ▏         |
| s22         | router        | WGr   |    3        |    2        | ⚠️ 1M   ▏         |
| s22 4G WG   | nas           | WGr   |    —        |    3        | ⚠️ 1M   ▏         |

🧭 Legend
Iface (Interface)
- LAN — Local network path
- WAN — Internet path
- WGr — WireGuard on router


# Appendix with archived content, most probably updated

## sudo apt

sudo apt update
sudo apt install -y shellcheck

## Core DNS (experimental)

We use CoreDNS to provide DOH for our DNS

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
