#!/usr/bin/env bash
# sudo /usr/local/bin/setup-headscale.sh
# Idempotent Headscale system user/group and directory setup script
#
# to deploy use
#     sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/setup-headscale.sh /usr/local/bin/
#     sudo chown root:root /usr/local/bin/setup-headscale.sh;sudo chmod 700 /usr/local/bin/setup-headscale.sh
#
# Prerequisites:
#   - Requires root privileges (sudo).
#   - Headscale binary installed at /usr/local/bin/headscale.
#
# Usage:
#   sudo setup-headscale.sh        # ensures user/group exist, fixes ownership of /var/lib/headscale and /etc/headscale
#
# Short notes:
# - Creates system group 'headscale' if missing.
# - Creates system user 'headscale' if missing, with home /var/lib/headscale and shell /usr/sbin/nologin.
# - Ensures directories /var/lib/headscale and /etc/headscale exist and are owned by headscale:headscale.
# - Safe to run multiple times (idempotent).
# - Recommended to run before enabling systemd unit with User=headscale / Group=headscale.
set -euo pipefail

echo "🔧 Starting Headscale setup..."

# Ensure group exists
if ! getent group headscale >/dev/null; then
    echo "➕ Creating group: headscale"
    sudo groupadd --system headscale
else
    echo "✅ Group 'headscale' already exists"
fi

# Ensure user exists
if ! id -u headscale >/dev/null 2>&1; then
    echo "➕ Creating user: headscale"
    sudo useradd --system \
        --home-dir /var/lib/headscale \
        --shell /usr/sbin/nologin \
        --gid headscale \
        headscale
else
    echo "✅ User 'headscale' already exists"
fi

# Ensure working directories exist and are owned correctly
for dir in /var/lib/headscale /etc/headscale; do
    if [ ! -d "$dir" ]; then
        echo "📂 Creating directory: $dir"
        sudo mkdir -p "$dir"
    else
        echo "✅ Directory $dir already exists"
    fi

    # Check current ownership
    owner=$(stat -c "%U" "$dir")
    group=$(stat -c "%G" "$dir")

    if [ "$owner" = "headscale" ] && [ "$group" = "headscale" ]; then
        echo "✅ Ownership already correct for $dir → $owner:$group"
    else
        echo "🔒 Fixing ownership for $dir (was $owner:$group → headscale:headscale)"
        sudo chown -R headscale:headscale "$dir"
    fi
done

echo "🎉 Headscale setup complete"
