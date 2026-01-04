#!/usr/bin/env bash
set -euo pipefail

die()  { echo "wg-client-export: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

# wg-client-export.sh — emit client configs from compiled intent (plan.tsv)
#
# Reads:
#   /volume1/homelab/wireguard/compiled/plan.tsv
#   /volume1/homelab/wireguard/compiled/keys.tsv
#   /volume1/homelab/wireguard/compiled/server-pubkeys/wgX.pub
#
# Writes:
#   /volume1/homelab/wireguard/export/clients/<base>/<iface>.conf
#
# This script is a DUMB RENDERER.
# No address math. No policy. No inference.

ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"

WG_PUBDIR="$ROOT/compiled/server-pubkeys"
KEYS_TSV="$ROOT/compiled/keys.tsv"
OUT_ROOT="$ROOT/export/clients"

need "$PLAN"
need "$KEYS_TSV"

WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_DNS="${WG_DNS:-}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"

mkdir -p "$OUT_ROOT"
umask 077

# --------------------------------------------------------------------
# Validate strict TSV header
# --------------------------------------------------------------------
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

# --------------------------------------------------------------------
# Render client configs
# --------------------------------------------------------------------
awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }

	$1=="base" &&
	$2=="iface" &&
	$3=="hostid" &&
	$4=="dns" &&
	$5=="client_addr4" &&
	$6=="client_addr6" &&
	$7=="AllowedIPs_client" &&
	$8=="AllowedIPs_server" &&
	$9=="endpoint" { next }

	{
		print $1 "\t" $2 "\t" $4 "\t" $5 "\t" $7 "\t" $9
	}
' "$PLAN" | while IFS=$'\t' read -r base iface dns addr4 allowed endpoint; do

	[ -n "$base" ]  || die "plan.tsv: missing base"
	[ -n "$iface" ] || die "plan.tsv: missing iface for base=$base"
	[ -n "$addr4" ] || die "plan.tsv: missing client_addr4 for $base $iface"
	[ -n "$allowed" ] || die "plan.tsv: missing AllowedIPs_client for $base $iface"

	srv_pub="$WG_PUBDIR/$iface.pub"
	need "$srv_pub"

	server_public="$(tr -d '\r\n' <"$srv_pub")"

	client_private="$(
		awk -F'\t' \
			-v base="$base" \
			-v iface="$iface" \
			'$1==base && $2==iface {print $3}' \
			"$KEYS_TSV"
	)"

	[ -n "$client_private" ] || \
		die "missing client private key for $base $iface in keys.tsv"

	out_dir="$OUT_ROOT/$base"
	mkdir -p "$out_dir"
	out="$out_dir/$iface.conf"

	{
		echo "# ${base}-${iface}"
		echo
		echo "[Interface]"
		echo "PrivateKey = $client_private"
		echo "Address = $addr4"
		echo "DNS = ${WG_DNS:-$dns}"
		echo
		echo "[Peer]"
		echo "PublicKey = $server_public"
		echo "AllowedIPs = $allowed"
		echo "Endpoint = ${WG_ENDPOINT:-$endpoint}"
		echo "PersistentKeepalive = $WG_PERSISTENT_KEEPALIVE"
	} >"$out"

	chmod 600 "$out"
	echo "wg-client-export: wrote $out"
done
