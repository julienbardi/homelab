#!/bin/sh
# ============================================================
# detect-unauthorized-lan-ips.sh — ensure no hardcoded LAN IPs
# ============================================================
# LAN topology invariants — authoritative IP validation
# - Authoritative LAN IPs come ONLY from config.mk
# - No file in the repo may contain 10.89.12.X unless declared
# - BusyBox-safe, POSIX, no arrays, no bashisms
# ============================================================

set -eu

# Resolve repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load authoritative LAN IPs from config.mk
# We only extract LAN_* variables
AUTHORIZED="$(
    awk '
        /^export LAN_/ {
            # Example: export LAN_NAS := 10.89.12.4
            gsub(/.*:= */, "", $0);
            print $0;
        }
    ' "$REPO_ROOT/mk/config.mk"
)"

# If nothing extracted → fail hard
if [ -z "$AUTHORIZED" ]; then
    echo "❌ No LAN_* variables found in config.mk — cannot validate LAN IPs"
    exit 1
fi

# Build grep pattern for LAN subnet
LAN_PREFIX="10\\.89\\.12\\."

# Temporary file for matches
tmp_matches="$(mktemp)"
trap 'rm -f "$tmp_matches"' EXIT INT TERM

# Search repo for LAN IPs (excluding .git and binary files)
grep -RhoE "$LAN_PREFIX[0-9]+" "$REPO_ROOT" \
    --exclude-dir=".git" \
    --exclude="*.png" \
    --exclude="*.jpg" \
    --exclude="*.jpeg" \
    --exclude="*.gif" \
    --exclude="*.ico" \
    --exclude="*.pdf" \
    > "$tmp_matches" || true

# If no matches → OK
if ! [ -s "$tmp_matches" ]; then
    echo "♻️  No LAN IPs found in repo — OK"
    exit 0
fi

# Check each match against the authorized list
errors=0

while IFS= read -r ip; do
    # Skip empty lines
    [ -z "$ip" ] && continue

    # Check if IP is authorized
    echo "$AUTHORIZED" | grep -qx "$ip" && continue

    # If not authorized → find file(s) containing it
    echo "❌ Unauthorized LAN IP detected: $ip"
    grep -Rnl "$ip" "$REPO_ROOT" --exclude-dir=".git" || true
    errors=1
done < "$tmp_matches"

if [ "$errors" -ne 0 ]; then
    echo "❌ LAN topology violation detected"
    echo "   → All LAN IPs must originate from config.mk (LAN_*)"
    exit 1
fi

echo "✅ All LAN IPs match authoritative declarations"
exit 0
