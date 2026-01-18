#!/bin/sh
set -eu

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"
BASE_DIR="$WG_ROOT/out/server/base"
PEERS_DIR="$WG_ROOT/out/server/peers"

die() { echo "wg-check-render: ERROR: $*" >&2; exit 1; }

[ -f "$PLAN" ] || die "missing $PLAN"
[ -d "$BASE_DIR" ] || die "missing $BASE_DIR"
[ -d "$PEERS_DIR" ] || die "missing $PEERS_DIR"

ifaces="$(
	awk '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" && $3=="slot" &&
		$4=="dns" && $5=="client_addr4" && $6=="client_addr6" &&
		$7=="AllowedIPs_client" && $8=="AllowedIPs_server" &&
		$9=="endpoint" { next }
		{ print $2 }
	' "$PLAN" | sort -u
)"

[ -n "$ifaces" ] || die "no interfaces found in plan.tsv"

for iface in $ifaces; do
	base="$BASE_DIR/$iface.conf"
	peers="$PEERS_DIR/$iface"

	[ -f "$base" ] || die "missing base config: $base"
	[ -d "$peers" ] || die "missing peer dir: $peers"

	# Base config must contain exactly one placeholder
	count="$(grep -c '^PrivateKey = __REPLACED_AT_DEPLOY__$' "$base" || true)"
	[ "$count" -eq 1 ] || die "$base must contain exactly one PrivateKey placeholder"

	# Base config must not contain peers
	if grep -Fq '[Peer]' "$base"; then
		die "$base must not contain [Peer] sections"
	fi

	# Must have at least one peer rendered
	if ! find "$peers" -type f -name '*.conf' -print -quit | grep -q .; then
		die "no peer configs found in $peers"
	fi
done
