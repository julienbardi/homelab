# Homelab Scripts

This repository contains reproducible, idempotent scripts for managing Julien’s homelab.  
All scripts are designed to be run with `sudo` and source a single configuration file (`config/homelab.env`).

---

## 📦 Prerequisites

- Linux host with `systemd`
- `sudo` privileges
- `make` installed
- Required tools: `iptables`, `ip6tables`, `jq`, `openssl`, `qrencode`, `tailscale`, `headscale`, `acme.sh`

---

## 🚀 Usage & Quickstart

The `Makefile` wraps all commands. Below are the available targets and a quickstart workflow to bootstrap a fresh machine:

```bash
make all                 # Deploy everything
make setup               # Run setup-homelab.sh
make dnsmasq             # Deploy dnsmasq-homelab.service
make firewall            # Apply firewall rules

# WireGuard
make wireguard-init
make wireguard-add NAME=laptop
make wireguard-list
make wireguard-remove NAME=laptop

# Tailscale / Headscale
make tailscale
make headscale-new NAME=nas
make headscale-list
make headscale-revoke ARG=<id|machine>
make headscale-show NAME=nas
make headscale-qr NAME=nas

# Certificates
make certs-all
make certs-issue
make certs-deploy
make certs-validate

# Status / Cleanup
make status
make clean
make reset-state

# Subnet Router
make subnet-router-service
make aliases
```

---

## 🧭 Quickstart Workflow

```bash
cd /home/julie/homelab/scripts
make all
make wireguard-init
make wireguard-add NAME=laptop
make headscale-new NAME=nas
make tailscale
make certs-all
make status
```

---

## 🧩 Client block markers for WireGuard

```ini
# laptop BEGIN
[Peer]
PublicKey = <client_pubkey>
AllowedIPs = 10.4.0.2/32
# laptop END
```

The `wireguard-remove` target uses these markers to delete the block, remove the live peer, and restart the interface.
