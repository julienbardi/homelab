# Homelab Setup — bardi.ch

This README documents the scripts, aliases, and operational hints used to configure and maintain the bardi.ch homelab. All components are designed for idempotency, auditability, and cross-platform onboarding.

---

## 🧩 Scripts

| Script | Purpose |
|--------|--------|
| `setup-headscale.sh` | Installs Headscale v0.27.0-beta.1 with SQLite, IPv6-safe config, and audit logging |
| `setup-dnsmasq-nas.sh` | Configures dnsmasq to resolve `.bardi.ch` hostnames locally and forward to Quad9 |
| `setup-subnet-router.sh` | Advertises LAN subnet via Tailscale, tunes GRO, restarts dnsmasq, and logs version |
| `setup-acl.sh` | Generates Headscale ACL config with autogroup support and tag ownership |
| `setup-firewall.sh` | Applies and persists iptables rules, configures logrotate, and backs up Headscale DB |
| `setup-cron-healthcheck.sh` | Installs hourly cron job to verify Tailscale, dnsmasq, and subnet-router status |

---

## 🧠 Hostname Mapping (`.bardi.ch`)

| Hostname               | IP Address       | Device              |
|------------------------|------------------|---------------------|
| `diskstation.bardi.ch` | `192.168.50.2`   | Synology DS218play  |
| `qnap.bardi.ch`        | `192.168.50.3`   | QNAP TS210          |
| `router.bardi.ch`      | `192.168.50.1`   | Asus RT-AX86U       |
| `nas.bardi.ch`         | `192.168.50.4`   | Ugreen DXP4800+     |
| `headscale.bardi.ch`   | `192.168.50.4`   | Headscale service   |

---

## 🧪 Aliases

```bash
alias router-deploy='cp ~/setup-subnet-router.sh /usr/local/bin/setup-subnet-router.sh && systemctl restart subnet-router.service'
alias router-logs='journalctl -u subnet-router.service -f -n 50'
alias router-version='journalctl -u subnet-router.service | grep "Setup complete" | tail -1'
