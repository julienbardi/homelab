#!/usr/bin/env bash
# wg-seed-missing-keys.sh
set -euo pipefail

# shellcheck disable=SC1091
source /volume1/homelab/homelab.env
: "${WG_ROOT:?}"

PLAN="$WG_ROOT/compiled/plan.tsv"
KEYS="$WG_ROOT/compiled/keys.tsv"

umask 077

[ -f "$PLAN" ] || { echo "missing plan.tsv"; exit 1; }
[ -f "$KEYS" ] || { echo "missing keys.tsv"; exit 1; }

awk -F'\t' '
    BEGIN { OFS="\t" }
    FNR==NR {
        if ($1=="base" && $2=="iface") next
        have[$1 SUBSEP $2]=1
        next
    }
    /^#/ || NF==0 { next }
    ($1=="node" && $2=="iface") { next }
    {
        key=$1 SUBSEP $2
        if (!(key in have)) print $1, $2
    }
' "$KEYS" "$PLAN" | while IFS=$'\t' read -r base iface; do
    echo "🔑 seeding key for $base $iface"
    priv="$(wg genkey)"
    pub="$(printf '%s' "$priv" | wg pubkey)"
    printf "%s\t%s\t%s\t%s\n" "$base" "$iface" "$pub" "$priv" >>"$KEYS"
done
