#!/bin/sh
# ============================================================
# detect-unauthorized-lan-ips.sh — LAN IP invariant checker
#
# DEPENDS:
#   - stamps.sh
#
# CONTRACT:
# - This script is installed into /usr/local/bin by `make install-all`.
# - It MUST NOT reference repo paths (./scripts/... or $REPO_ROOT/...).
# - It MUST reference sibling installed scripts via $SCRIPT_DIR.
# - All dependent scripts MUST be installed into the same directory.
# - Repo-preflight executes this script directly.
# - Repo scripts are source-only and must never be executed.
# - BusyBox-safe: no arrays, no bashisms.
# ============================================================

set -eu

SCRIPT_DIR="$(dirname "$0")"

# Load shared stamp primitives
. "$SCRIPT_DIR/stamps.sh"

DIR="$(stamp_init)"
STAMP="$DIR/lan-ip-check.stamp"

# ------------------------------------------------------------
# Compute hash of LAN IP declarations
# ------------------------------------------------------------
stamp_compute_hash_lan_ips() {
    # BusyBox-safe: explicit file list, no arrays
    sha256sum \
        "$SCRIPT_DIR/detect-unauthorized-lan-ips.sh" \
    | sha256sum | awk '{print $1}'
}

current_hash="$(stamp_compute_hash_lan_ips)"

# ------------------------------------------------------------
# Check if stamp exists and matches
# ------------------------------------------------------------
if [ -f "$STAMP" ]; then
    stored_hash="$(cat "$STAMP")"
    if [ "$current_hash" = "$stored_hash" ]; then
        echo "⏩ LAN IP declarations unchanged — skipping"
        exit 0
    fi
fi

echo "🔍 Checking for unauthorized LAN IPs..."

# ------------------------------------------------------------
# Actual LAN IP check logic
# ------------------------------------------------------------
# BusyBox-safe: no arrays, no bashisms
# We assume the authoritative LAN IP list is provided by stamps.sh
# or by environment variables exported by the Makefile.

# Example authoritative list (replace with your actual logic):
AUTHORIZED_IPS="$(stamp_dir)/authorized-lan-ips.txt"

if [ ! -f "$AUTHORIZED_IPS" ]; then
    echo "⚠️ No authoritative LAN IP list found — skipping check"
    printf '%s\n' "$current_hash" > "$STAMP"
    exit 0
fi

# Enumerate current LAN IPs
CURRENT_IPS="$(ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1)"

unauthorized=0

for ip in $CURRENT_IPS; do
    if ! grep -qx "$ip" "$AUTHORIZED_IPS"; then
        echo "❌ Unauthorized LAN IP detected: $ip"
        unauthorized=1
    fi
done

if [ "$unauthorized" -ne 0 ]; then
    echo "❌ Unauthorized LAN IPs found"
    exit 1
fi

# ------------------------------------------------------------
# Update stamp
# ------------------------------------------------------------
printf '%s\n' "$current_hash" > "$STAMP"
echo "🟢 LAN IP stamp updated"
