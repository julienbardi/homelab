#!/usr/bin/env bash
set -euo pipefail

die()  { echo "wg-client-export: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

# wg-client-export.sh — emit client configs from compiled intent
#
# This script is a DUMB RENDERER.
# No address math. No policy. No inference.
# All schema validation is delegated to wg-plan-read.sh.

: "${WG_ROOT:?WG_ROOT not set}"

PLAN_READER="$(dirname "$0")/wg-plan-read.sh"

WG_PUBDIR="$WG_ROOT/compiled/server-pubkeys"
KEYS_TSV="$WG_ROOT/compiled/keys.tsv"
OUT_ROOT="$WG_ROOT/export/clients"

need "$PLAN_READER"
need "$KEYS_TSV"

WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_DNS="${WG_DNS:-}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"

mkdir -p "$OUT_ROOT"
umask 077

# --------------------------------------------------------------------
# Render client configs from canonical plan reader
# --------------------------------------------------------------------
"$PLAN_READER" | while IFS=$'\t' read -r \
	base iface slot dns addr4 addr6 allowed_client allowed_server endpoint
do
	[ -n "$base" ]  || die "missing base"
	[ -n "$iface" ] || die "missing iface for base=$base"
	[ -n "$addr4" ] || die "missing client_addr4 for $base $iface"
	[ -n "$allowed_client" ] || die "missing AllowedIPs_client for $base $iface"

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

	tmp="$(mktemp "${out}.XXXXXX")"

	{
		echo "# ${base}-${iface}"
		echo
		echo "[Interface]"
		echo "PrivateKey = $client_private"
		echo "Address = $addr4"
		if [ -n "${WG_DNS:-$dns}" ]; then
			echo "DNS = ${WG_DNS:-$dns}"
		fi
		echo
		echo "[Peer]"
		echo "PublicKey = $server_public"
		echo "AllowedIPs = $allowed_client"
		echo "Endpoint = ${WG_ENDPOINT:-$endpoint}"
		echo "PersistentKeepalive = $WG_PERSISTENT_KEEPALIVE"
	} >"$tmp"

	chmod 600 "$tmp"

	if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
		rm -f "$tmp"
		echo "wg-client-export: ⚪ unchanged $out"
	else
		mv -f "$tmp" "$out"
		echo "wg-client-export: 🟢 updated   $out"
	fi
done
