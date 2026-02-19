#!/usr/bin/env bash
# wg-check.sh
set -euo pipefail

# shellcheck disable=SC1091
source /volume1/homelab/homelab.env
: "${WG_ROOT:?WG_ROOT not set}"

ROOT="$WG_ROOT"

PLAN="$ROOT/compiled/plan.v2.tsv"
ALLOC="$ROOT/compiled/alloc.csv"
KEYS="$ROOT/compiled/keys.tsv"

SERVER_PUBDIR="$ROOT/compiled/server-pubkeys"

: "${VERBOSE:=0}"

say() { if [ "$VERBOSE" -ge 1 ]; then echo "$@"; fi; }
die() { echo "wg-check: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ]  || die "missing plan.v2.tsv"
[ -f "$ALLOC" ] || die "missing alloc.csv"
[ -f "$KEYS" ] || die "missing keys.tsv"

say "🔍 checking plan.v2.tsv header"

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
' "$PLAN" || die "plan.v2.tsv header does not match strict TSV contract"

say "🔍 checking plan.v2.tsv ↔ alloc.csv consistency"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $1 }
' "$PLAN" | sort -u | while read -r base; do
	grep -q "^$(printf '%s' "$base" | sed 's/[.[\*^$]/\\&/g')," "$ALLOC" || die "base '$base' missing from alloc.csv"
done

say "🔍 checking server public keys"

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $2 }
' "$PLAN" | sort -u | while read -r iface; do
	[ -f "$SERVER_PUBDIR/$iface.pub" ] || die "missing server pubkey $iface.pub"
done

say "🔍 checking client keys (keys.tsv)"

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

say "🔍 checking for orphan client keys (keys.tsv)"

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
		echo "⚠️  wg-check: orphan client key $base $iface"
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

# Guard: no global IPv6 must ever be routed via WireGuard
if ip -6 route show \
	| grep -E 'wg[0-9]+' \
	| grep -Ev 'fd89:7a3b:42c0:' \
	>/dev/null
then
	echo "❌ wg-check: global IPv6 route leaked into WireGuard" >&2
	ip -6 route show | grep -E 'wg[0-9]+' | grep -Ev 'fd89:7a3b:42c0:' >&2
	exit 1
fi
