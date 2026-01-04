#!/usr/bin/env bash
set -euo pipefail

ROOT="/volume1/homelab/wireguard"

PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"

SERVER_PUBDIR="$ROOT/compiled/server-pubkeys"
CLIENT_KEYDIR="$ROOT/compiled/client-keys"

die() { echo "wg-check: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ]  || die "missing plan.tsv"
[ -f "$ALLOC" ] || die "missing alloc.csv"

echo "• checking plan.tsv header"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	!seen {
		seen=1
		if ($1=="base" &&
			$2=="iface" &&
			$3=="hostid" &&
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
	grep -q "^$base," "$ALLOC" || die "base '$base' missing from alloc.csv"
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

echo "• checking client private keys"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $1 "-" $2 }
' "$PLAN" | while read -r pair; do
	[ -f "$CLIENT_KEYDIR/$pair.key" ] || die "missing client key $pair.key"
done

echo "• checking for orphan client keys"

ls "$CLIENT_KEYDIR"/*.key 2>/dev/null | while read -r key; do
	name="$(basename "$key" .key)"
	if ! awk -F'\t' '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		{ if ($1 "-" $2 == NAME) found=1 }
		END { exit(found?0:1) }
	' NAME="$name" "$PLAN"; then
		echo "wg-check: WARN: orphan client key $name.key"
	fi
done || true

echo "wg-check: OK"
