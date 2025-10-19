# Homelab

This repository contains scripts and supporting files I use to manage and automate my homelab environment.  
The focus is on **clarity, reproducibility, and auditability** — every script is self‑contained, idempotent, and integrates with `systemd` where appropriate.

---

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


##Repo Structure
homelab/
├── scripts/        # Automation scripts (currently only setup-subnet-router.sh)
├── .gitignore      # Ignore rules for logs, temp files, NAS sync dbs, etc.
└── README.md       # Project overview and usage


---

## ✅ Next Step

1. Create the file in your repo root:
   ```bash
   cd ~/homelab
   nano README.md
