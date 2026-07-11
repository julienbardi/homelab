#!/bin/sh
# pve-repo-converge
# Deterministic Proxmox repository + GPG key converge
# Julien Bardi — Homelab Identity Contract

set -e

PVE_KEY_FINGERPRINT="24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E"
PVE_KEY_PATH="/etc/apt/trusted.gpg.d/proxmox-release.gpg"
PVE_REPO="/etc/apt/sources.list.d/pve.list"

echo "🔧 pve-repo-converge: enforcing Proxmox repository identity"

# Validate Debian release
DEB_RELEASE=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
echo "🔧 Debian release detected: ${DEB_RELEASE}"

if [ "$DEB_RELEASE" != "trixie" ]; then
    echo "❌ Unexpected Debian release '$DEB_RELEASE' — aborting"
    exit 1
fi

# Validate Proxmox repo file
if [ ! -f "$PVE_REPO" ]; then
    echo "🔧 Creating Proxmox repo file"
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > "$PVE_REPO"
fi

# Validate GPG key
if ! gpg --show-keys "$PVE_KEY_PATH" 2>/dev/null | grep -q "$PVE_KEY_FINGERPRINT"; then
    echo "🔧 Installing Proxmox Trixie GPG key"
    wget -qO "$PVE_KEY_PATH" \
      https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg
else
    echo "✅ Proxmox GPG key already installed"
fi

# Remove invalid UGOS leftovers
echo "🔧 Removing invalid UGOS sources"
sed -i '/ugreen/d' /etc/apt/sources.list || true
sed -i '/alpine/d' /etc/apt/sources.list || true

# Update package lists
echo "🔄 Running apt update"
apt update

echo "🟢 pve-repo-converge complete"
