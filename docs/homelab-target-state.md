# 🏡 Homelab Target State
<!-- 
Hit Ctrl+Alt+V to preview this file in Visual Studio Code 
or browse https://github.com/Jambo15/homelab/blob/main/docs/homelab-handbook.md 
-->
## 🌐 Network & Infrastructure
- **Router**: Asus RT‑AX86U  
  - Provides IPv4/IPv6 connectivity  
  - Static DHCP leases for all critical nodes  
  - Delegated IPv6 prefix for predictable addressing  
  - Port forwarding only for explicitly approved services

- **LAN Subnet**: `192.168.50.0/24`  
  - Predictable addressing for all nodes  
  - Conflict detection logic in subnet router script  
  - Docker subnets auto‑excluded if overlapping

---

## 🖥️ Core Nodes

| Device              | Role                          | Notes                                      |
|---------------------|-------------------------------|--------------------------------------------|
| Synology DS218play  | NAS, Headscale host           | SSL certs via `bardi_cert.sh`              |
| QNAP TS210          | Legacy storage                |                                            |
| Ugreen DXP4800+     | Primary storage & backups     |                                            |
| Windows 11 PCs      | Clients                       | Headscale/Tailscale endpoints              |
| Android phones      | Clients                       | Headscale/Tailscale endpoints              |

---

## 📛 DNS & Identity
- **Authoritative DNS**  
  - Explicit A records for each LAN node  
  - CNAMEs for service aliases (no ambiguity)  
  - Internal DNS resolution via `dnsmasq`

- **Domain**: `*.bardi.ch`  
  - Internal services mapped consistently  
  - External exposure only for selected services

---

## 🔒 Certificates & Security
- **Certificate Management**  
  - `bardi_cert.sh` handles issuance/renewal  
  - DNS‑based validation (Infomaniak API)  
  - Multi‑node deployment with audit logging  
  - Timestamp + version tag echoed on each deploy

- **Secrets**  
  - No secrets in GitHub repo (only configs & docs)  
  - API tokens, pre‑auth keys, and private keys stored securely outside repo

---

## 📡 Subnet Router Service
- **Script**: `/usr/local/bin/setup-subnet-router.sh`  
  - Auto‑incrementing version tag  
  - Logs version + timestamp at boot (systemd)  
  - Conflict detection for overlapping subnets  
  - NAT, dnsmasq restart, Tailscale advertisement, GRO tuning  
  - Footer echo lines for audit clarity

- **Systemd Service**  
  - Logs version at boot for easy grepping  
  - Aliases:  
    - `router-logs` → tails live logs of `subnet-router.service`  
    - `router-deploy` → copies updated script from `~/` to `/usr/local/bin/` and restarts service

---

## 🌍 Exposure & Access
- **Internal‑only services**: Headscale, admin dashboards  
- **Internet‑exposed services**: Only those explicitly mapped with SSL certs and port forwarding  
- **Tailscale**: Provides secure remote access without exposing management interfaces

---

## 📂 Documentation & Repo Structure

The repository is organized to keep **design docs, configs, and scripts** cleanly separated, with this handbook serving as the master reference.

```text
homelab/
├── docs/
│   ├── homelab-handbook.md      # Master design brief (this file)
│   ├── architecture-overview.md # Optional ASCII diagram or visuals
│   ├── audit-checklist.md       # Quick verification steps
│   └── troubleshooting.md       # Common issues and resolutions
│
├── configs/
│   ├── dnsmasq.conf             # Internal DNS mappings
│   ├── dhcp-static.conf         # Static DHCP leases
│   ├── systemd-units/           # Unit files for subnet router, cert service
│   └── tailscale/               # Headscale/Tailscale configs
│
├── scripts/
│   ├── setup-subnet-router.sh   # Subnet router logic (versioned, logged)
│   └── bardi_cert.sh            # Centralized cert issuance/renewal
│
└── logs/                        # (Optional) sanitized log samples for audits

---

## 📡 IP Address Mapping (LAN)

| Hostname             | IP Address       | Role / Notes                          |
|----------------------|------------------|---------------------------------------|
| router.bardi.ch      | 192.168.50.1     | Asus RT‑AX86U                         |
| nas.bardi.ch         | 192.168.50.4     | Ugreen DXP4800+ (primary storage, Headscale host)                         |
| diskstation.bardi.ch | 192.168.50.2     | Synology DS218play (Headscale client)   |
| qnap.bardi.ch        | 192.168.50.3     | QNAP TS210 (legacy storage)           |

> **Note:** All static DHCP leases are configured on the Asus RT‑AX86U.  
> IPv6 addresses are delegated and predictable, but not listed here for brevity.

---

## 🌐 Public DNS (Informaniak)

### A Records
- `bardi.ch` → updated dynamically by teh router 192.168.50.1

### CNAME Records
- `headscale.bardi.ch` → `bardi.ch`  

> **Note:** Only expose services that are hardened and SSL‑protected.  
> Internal‑only hostnames (like `diskstation.bardi.ch`) remain LAN‑only and are not published to Informaniak.

---

## ✅ Summary
- **LAN IPs** are fixed and documented for every node.  
- **Public DNS** is minimal, with A records pointing to the router’s WAN IP and CNAMEs providing service aliases.  
- **Informaniak DNS** is the single external source of truth, while `dnsmasq` handles internal resolution.