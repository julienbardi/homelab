#!/usr/bin/env bash
# wg-check.sh
set -euo pipefail

# shellcheck disable=SC1091
source /volume1/homelab/homelab.env
: "${WG_ROOT:?WG_ROOT not set}"

ROOT="$WG_ROOT"

PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"
KEYS="$ROOT/compiled/keys.tsv"

SERVER_PUBDIR="$ROOT/compiled/server-pubkeys"

: "${VERBOSE:=0}"

say() { if [ "$VERBOSE" -ge 1 ]; then echo "$@"; fi; }
die() { echo "wg-check: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ]  || die "missing plan.tsv"
[ -f "$ALLOC" ] || die "missing alloc.csv"
[ -f "$KEYS" ]  || die "missing keys.tsv"

# Canonical plan reader (must be on PATH via wg-install-scripts)
PLAN_READ() { wg-plan-read.sh "$PLAN"; }

# --------------------------------------------------------------------
# plan.tsv ↔ alloc.csv consistency
# --------------------------------------------------------------------

say "🔍 checking plan.tsv ↔ alloc.csv consistency"

PLAN_READ | awk -F'\t' '{ print $1 }' | sort -u | while read -r base; do
    grep -q "^$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')," "$ALLOC" \
        || die "base '$base' missing from alloc.csv"
done

# --------------------------------------------------------------------
# Server public keys
# --------------------------------------------------------------------

say "🔍 checking server public keys"

PLAN_READ | awk -F'\t' '{ print $2 }' | sort -u | while read -r iface; do
    [ -f "$SERVER_PUBDIR/$iface.pub" ] || die "missing server pubkey $iface.pub"
done

# --------------------------------------------------------------------
# Client keys (keys.tsv)
# --------------------------------------------------------------------

say "🔍 checking client keys (keys.tsv)"

PLAN_READ | awk -F'\t' '{ print $1 "\t" $2 }' | while read -r base iface; do
    awk -F'\t' -v b="$base" -v i="$iface" '
        /^#/ { next }
        /^[[:space:]]*$/ { next }
        $1=="base" && $2=="iface" { next }
        $1==b && $2==i { found=1 }
        END { exit(found?0:1) }
    ' "$KEYS" || die "missing client key for $base $iface in keys.tsv"
done

# --------------------------------------------------------------------
# Orphan client keys
# --------------------------------------------------------------------

say "🔍 checking for orphan client keys (keys.tsv)"

awk -F'\t' '
    /^#/ { next }
    /^[[:space:]]*$/ { next }
    $1=="base" && $2=="iface" { next }
    { print $1 "\t" $2 }
' "$KEYS" | while read -r base iface; do
    if ! PLAN_READ | awk -F'\t' -v b="$base" -v i="$iface" '
        $1==b && $2==i { found=1 }
        END { exit(found?0:1) }
    '; then
        echo "� ️  wg-check: orphan client key $base $iface"
    fi
done

# --------------------------------------------------------------------
# Guard: LAN prefixes must never be routed via WireGuard
# --------------------------------------------------------------------

if ip route show | grep -Eq '10\.89\.12\.0/24.*wg' >/dev/null; then
    echo "❌ wg-check: LAN IPv4 route leaked into WireGuard" >&2
    ip route show | grep -E '10\.89\.12\.0/24.*wg' >&2
    exit 1
fi

# --------------------------------------------------------------------
# Guard: no global IPv6 must ever be routed via WireGuard
# --------------------------------------------------------------------

if ip -6 route show \
    | grep -E 'wg[0-9]+' \
    | grep -Ev 'fd89:7a3b:42c0:' \
    >/dev/null
then
    echo "❌ wg-check: global IPv6 route leaked into WireGuard" >&2
    ip -6 route show | grep -E 'wg[0-9]+' | grep -Ev 'fd89:7a3b:42c0:' >&2
    exit 1
fi
