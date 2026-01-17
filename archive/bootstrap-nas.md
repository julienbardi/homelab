# Bootstrap Guide for NAS (UGOS / DXP4800+)

This document describes the ## manual steps required to bring a fresh NAS online before the automated homelab stack (`make deps`, subnet‑router, services, etc.) can run.  
It is the authoritative bootstrap sequence for a clean UGOS system.

---

# 1. Configure LAN1 (Router‑Connected Interface)

LAN1 is the primary interface for:
- Internet access  
- Package installation  
- Git operations  
- WireGuard and Tailscale egress  
- IPv6 delegated prefix routing  

Assign:
- IPv4: `10.89.12.4/24`  
- Gateway: `10.89.12.1`  
- DNS: router or upstream  
- IPv6: delegated prefix `2a01:8b81:4800:9c00::/64` (router RA)

Verify:

`ping -c3 10.89.12.1`  
`ping -c3 1.1.1.1`  
`curl https://example.com`

LAN2 is not used right now. Assign an address and gateway on an unused subnet.
---

# 2. Install SSH Keys (Mandatory)

On NAS:
`mkdir -p ~/.ssh`  
`chmod 700 ~/.ssh`  
`touch ~/.ssh/authorized_keys`  
`chmod 600 ~/.ssh/authorized_keys`  
`nano ~/.ssh/authorized_keys`

Paste your PC’s public key (`id_ed25519.pub`).

Test:
`ssh -p2222 julie@10.89.12.4`

---

# 3. Allow SSH Through UGOS Firewall

UGOS regenerates nftables rules at boot.  
We override them safely using a systemd oneshot.

Create:

`sudo nano /usr/local/bin/ug-firewall-override.sh`

Contents:

```
#!/bin/sh
nft add rule ip filter UG_INPUT iifname "eth1" tcp dport 2222 accept
nft add rule ip filter UG_INPUT iifname "eth0" tcp dport 2222 accept
```

Enable:
```
sudo chmod +x /usr/local/bin/ug-firewall-override.sh
sudo nano /etc/systemd/system/ug-firewall-override.service
```
Paste:

```
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

Activate:

```
sudo systemctl daemon-reload
sudo systemctl enable --now ug-firewall-override.service
```

---

# 5. Apply Required Kernel Networking Settings

UGOS is multi‑homed → asymmetric routing must be allowed.

Create:

`sudo nano /etc/sysctl.d/99-ug-multilan.conf`

Contents:

```
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.eth0.rp_filter = 2
net.ipv4.conf.eth1.rp_filter = 2

net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
```

Apply:

`sudo sysctl --system`

---

# 6. Install Git (Safe on UGOS), make (for `make deps`), unbound-anchor(for Unbound)
UGOS does not ship with `git`, `make`, `unbound-anchor`, so install them first.

`sudo apt-get update`  
`sudo apt-get install -y git make unbound-anchor --no-upgrade`

Clone the homelab repo:

```
mkdir -p ~/src
cd ~/src
git clone git@gitlab.com:jbardi/homelab.git
cd homelab
```

Configure Git identity:
```
git config --global user.name "Jambo15"
git config --global user.email "Jambo15@users.noreply.github.com"
```

🔀 Configure dual remotes (GitLab primary, GitHub mirror)
Your repo currently clones from GitLab, so origin already points to GitLab.

Rename it to github and re‑add GitLab as the primary,  set upstream tracking, verify

```bash
git remote rename origin github
git remote add origin git@gitlab.com:jbardi/homelab.git
git branch --set-upstream-to=origin/main
git remote -v
```
You should see:
```Code
origin  git@gitlab.com:jbardi/homelab.git (fetch)
origin  git@gitlab.com:jbardi/homelab.git (push)
github  git@github.com:Jambo15/homelab.git (fetch)
github  git@github.com:Jambo15/homelab.git (push)
```

🚀 Push workflow:
GitLab (origin) is primary. GitHub is a mirror.

`git push;git push github main`

If you want a single command later, you can add:

```bash
git config alias.pushboth '!git push && git push github main'
```
Then:

```bash
git pushboth
```

---

# 7. Run `make deps` (Installs All Required Packages)

From repo root:

`make deps`

This installs:

- ndppd  
- nftables  
- wireguard  
- unbound  
- tailscale  
- code-server  
- shellcheck  
- all Gen0/Gen1 dependencies  

---

# 8. WRONG: Deploy Subnet Router

Validate:

`router-logs`  
`nft list ruleset`  
`systemctl status ndppd`  
`ip -6 route`  
`wg show`

---

# 9. WRONG: Install VS Code Server (Manual UGOS Method)

Determine commit ID:

`code --version`

Create directory:

`mkdir -p ~/.vscode-server/bin/<commit>`

Download:

`curl -L https://update.code.visualstudio.com/commit:<commit>/server-linux-x64/stable -o vscode-server.tar.gz`

Extract:

`
tar -xzf vscode-server.tar.gz -C ~/.vscode-server/bin/<commit> --strip-components=1
rm vscode-server.tar.gz
`

Reconnect from VS Code.

---

# 10. Install code-server (Optional)

`curl -fsSL https://code-server.dev/install.sh | sh`  
`sudo systemctl enable --now code-server@$USER`

Edit:

`nano ~/.config/code-server/config.yaml`

Set:

`bind-addr: 0.0.0.0:8080`

---

# 11. Final Validation

`ssh -p2222 julie@10.89.12.4`
`nft list ruleset`  
`systemctl status ndppd`  
`wg show`  
`tailscale status`

If all succeed → NAS is fully bootstrapped.

Note:
- Caddy requires Go ≥ 1.21 and is installed under /usr/local/go via Makefile.

# 12. acme.sh (one-time)

Run as normal user (julie), not root:

```
curl https://get.acme.sh | sh
```

Infomaniak, click top right on your profiles, manage my account, then Developer, API tokens
vi ~/.acme.sh/account.conf

Add exactly this (replace the token):

```env
INFOMANIAK_API_TOKEN="YOUR_INFOMANIAK_API_TOKEN"
```

`chmod 600 ~/.acme.sh/account.conf`

Then on NAS:
```
cd ~/src/homelab
./scripts/setup/deploy_certificates.sh issue caddy
```
