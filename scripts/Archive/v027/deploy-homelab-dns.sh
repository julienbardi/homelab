#!/bin/bash
# -------------------------------------------------------------------
# File: deploy-homelab-dns.sh
# Purpose: Deploy or update the dedicated dnsmasq-homelab.service
# Author: julie
# -------------------------------------------------------------------

set -euo pipefail

SERVICE_FILE="/etc/systemd/system/dnsmasq-homelab.service"
VERSION_FILE="/etc/dnsmasq-homelab.version"

# --- Auto-increment version ---
if [[ -f "$VERSION_FILE" ]]; then
    VERSION=$(cat "$VERSION_FILE")
    MAJOR=$(echo "$VERSION" | cut -d. -f1)
    MINOR=$(echo "$VERSION" | cut -d. -f2)
    NEW_VERSION="$MAJOR.$((MINOR+1))"
else
    NEW_VERSION="1.0"
fi
echo "$NEW_VERSION" | sudo tee "$VERSION_FILE" > /dev/null

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "[*] Deploying dnsmasq-homelab v$NEW_VERSION at $TIMESTAMP"

# --- Write systemd unit ---
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Homelab dnsmasq instance (LAN resolver) v$NEW_VERSION
After=network.target

[Service]
ExecStart=/usr/sbin/dnsmasq -k \
  --conf-dir=/etc/dnsmasq.d \
  --pid-file=/run/dnsmasq-homelab.pid \
  --port=53
Restart=always

# Log version + timestamp at startup
ExecStartPost=/bin/echo "dnsmasq-homelab v$NEW_VERSION started at $TIMESTAMP"

[Install]
WantedBy=multi-user.target
EOF

# --- Reload and restart ---
sudo systemctl daemon-reexec
sudo systemctl enable --now dnsmasq-homelab.service

echo "[*] Status:"
systemctl --no-pager --full status dnsmasq-homelab.service || true

echo "[*] Active listeners on port 53:"
sudo ss -ltnup | grep ':53' || true
