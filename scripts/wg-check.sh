#!/usr/bin/env bash
set -euo pipefail

ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"
WG_DIR="/etc/wireguard"

die() { echo "wg-check: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ]  || die "missing plan.tsv"
[ -f "$ALLOC" ] || die "missing alloc.csv"

echo "• checking plan.tsv ↔ alloc.csv consistency"

awk -F'\t' '{print $1}' "$PLAN" | sort -u | while read -r base; do
	grep -q "^$base," "$ALLOC" || die "base '$base' missing from alloc.csv"
done

echo "• checking server keys"

for i in 0 1 2 3 4 5 6 7; do
	[ -f "$WG_DIR/wg$i.pub" ] || die "missing server key wg$i.pub"
done

echo "• checking client keys"

awk -F'\t' '{print $1 "-" $2}' "$PLAN" | while read -r pair; do
	[ -f "$WG_DIR/$pair.key" ] || die "missing client key $pair.key"
done

echo "• checking for orphan client keys"

ls "$WG_DIR"/*.key 2>/dev/null | grep -vE 'wg[0-7]\.key$' | while read -r key; do
	base="$(basename "$key" .key)"
	if ! grep -q "^${base%-wg*}\t${base#*-}" "$PLAN"; then
		echo "wg-check: WARN: orphan key $(basename "$key")"
	fi
done || true


echo "wg-check: OK"