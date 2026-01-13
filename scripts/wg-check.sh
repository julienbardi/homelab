#!/usr/bin/env bash
set -euo pipefail

ROOT="/volume1/homelab/wireguard"

PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"
KEYS="$ROOT/compiled/keys.tsv"

SERVER_PUBDIR="$ROOT/compiled/server-pubkeys"

die() { echo "wg-check: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ]  || die "missing plan.tsv"
[ -f "$ALLOC" ] || die "missing alloc.csv"
[ -f "$KEYS" ] || die "missing keys.tsv"

echo "• checking plan.tsv header"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	!seen {
		seen=1
		if ($1=="base" &&
			$2=="iface" &&
			$3=="slot" &&
			$4=="dns" &&
			$5=="client_addr4" &&
			$6=="client_addr6" &&
			$7=="AllowedIPs_client" &&
			$8=="AllowedIPs_server" &&
			$9=="endpoint") exit 0
		exit 1
	}
' "$PLAN" || die "plan.tsv header does not match strict TSV contract"

echo "• checking plan.tsv ↔ alloc.csv consistency"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $1 }
' "$PLAN" | sort -u | while read -r base; do
	grep -q "^$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')," "$ALLOC" || die "base '$base' missing from alloc.csv"
done

echo "• checking server public keys"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $2 }
' "$PLAN" | sort -u | while read -r iface; do
	[ -f "$SERVER_PUBDIR/$iface.pub" ] || die "missing server pubkey $iface.pub"
done

echo "• checking client keys (keys.tsv)"

awk -F'\t' '
	BEGIN { OFS="\t" }
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $1, $2 }
' "$PLAN" | while read -r base iface; do
	awk -F'\t' -v b="$base" -v i="$iface" '
		$1==b && $2==i { found=1 }
		END { exit(found?0:1) }
	' "$KEYS" || die "missing client key for $base $iface in keys.tsv"
done

echo "• checking for orphan client keys (keys.tsv)"

awk -F'\t' '
	/^#/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $1 "\t" $2 }
' "$KEYS" | while read -r base iface; do
	if ! awk -F'\t' -v b="$base" -v i="$iface" '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		$1==b && $2==i { found=1 }
		END { exit(found?0:1) }
	' "$PLAN"; then
		echo "wg-check: WARN: orphan client key $base $iface"
	fi
done

echo "wg-check: OK"
