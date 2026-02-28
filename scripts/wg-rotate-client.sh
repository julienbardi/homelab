#!/usr/bin/env bash
# wg-rotate-client.sh — explicit per-client key rotation
# Usage: wg-rotate-client.sh <base> <iface>
set -euo pipefail

# --------------------------------------------------------------------
# Environment + invariants
# --------------------------------------------------------------------
# shellcheck disable=SC1091
source /volume1/homelab/homelab.env

: "${WG_ROOT:?WG_ROOT not set}"
: "${SECURITY_DIR:?SECURITY_DIR not set}"

[ "$(id -u)" -eq 0 ] || {
    echo "wg-rotate-client: ERROR: must run as root" >&2
    exit 1
}

if [ $# -ne 2 ]; then
    echo "Usage: $0 <base> <iface>" >&2
    exit 1
fi

base="$1"
iface="$2"
key="${base}-${iface}"

KEYS="$WG_ROOT/compiled/keys.tsv"
LEDGER="$SECURITY_DIR/compromised_keys.tsv"

CLIENT_KEYS_DIR="$WG_ROOT/compiled/client-keys"
OUT_CLIENT="$WG_ROOT/out/clients"
OUT_SERVER="$WG_ROOT/out/server/peers"

# --------------------------------------------------------------------
# Validate existence in keys.tsv
# --------------------------------------------------------------------
if ! awk -F'\t' -v b="$base" -v i="$iface" '
    $1==b && $2==i { found=1 }
    END { exit(found?0:1) }
' "$KEYS"; then
    echo "wg-rotate-client: ERROR: no key entry for $base $iface in keys.tsv" >&2
    exit 1
fi

# --------------------------------------------------------------------
# Extract public key
# --------------------------------------------------------------------
pubkey="$(awk -F'\t' -v b="$base" -v i="$iface" '
    $1==b && $2==i { print $3 }
' "$KEYS")"

if [ -z "$pubkey" ]; then
    echo "wg-rotate-client: ERROR: failed to extract public key for $base $iface" >&2
    exit 1
fi

# --------------------------------------------------------------------
# Append to compromised ledger (status=rotated)
# --------------------------------------------------------------------
mkdir -p "$SECURITY_DIR"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf "%s\trotated\t%s\t%s\t%s\n" \
    "$pubkey" "$base" "$iface" "$timestamp" >>"$LEDGER"

# --------------------------------------------------------------------
# Remove entry from keys.tsv (atomic)
# --------------------------------------------------------------------
tmp_keys="$(mktemp)"
trap 'rm -f "$tmp_keys"' EXIT

awk -F'\t' -v b="$base" -v i="$iface" '
    BEGIN { OFS="\t" }
    $1==b && $2==i { next }
    { print }
' "$KEYS" >"$tmp_keys"

install -m 0600 -o root -g root "$tmp_keys" "$KEYS"

# --------------------------------------------------------------------
# Remove keypair files (idempotent)
# --------------------------------------------------------------------
rm -f "$CLIENT_KEYS_DIR/${key}.key" 2>/dev/null || true
rm -f "$CLIENT_KEYS_DIR/${key}.pub" 2>/dev/null || true

# --------------------------------------------------------------------
# Remove rendered configs (idempotent)
# --------------------------------------------------------------------
rm -f "$OUT_CLIENT/${key}.conf" 2>/dev/null || true
rm -f "$OUT_SERVER/$iface/$base.conf" 2>/dev/null || true

echo "🔁 Rotated WireGuard client: $base $iface"
echo "   - Old key added to compromised ledger"
echo "   - keys.tsv entry removed"
echo "   - keypair files removed"
echo "   - rendered configs removed"
echo "   - Run 'make wg' to generate a fresh keypair"
