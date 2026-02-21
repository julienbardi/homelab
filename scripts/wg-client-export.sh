#!/usr/bin/env bash
set -euo pipefail
: "${VERBOSE:=0}"

die()  { echo "wg-client-export: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

# wg-client-export.sh — emit client configs from compiled intent
#
# This script is a DUMB RENDERER.
# No address math. No policy. No inference.
# All schema validation is delegated to wg-plan-read.sh.
#
# CONTRACT:
# - Client exports are AUTHORITATIVE.
# - Every run regenerates the full set.
# - Any previously exported client config not present in the current plan
#   MUST be removed.

: "${WG_ROOT:?WG_ROOT not set}"
: "${PLAN:?wg-client-export: PLAN not set}"
: "${PLAN_READER:?wg-client-export: PLAN_READER not set}"

WG_PUBDIR="$WG_ROOT/compiled/server-pubkeys"
KEYS_TSV="$WG_ROOT/compiled/keys.tsv"

OUT_ROOT="$WG_ROOT/export/clients"
OUT_STAGE="$WG_ROOT/export/.clients.stage.$$"

need "$PLAN_READER"
need "$KEYS_TSV"

WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_DNS="${WG_DNS:-}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"

umask 077

# --------------------------------------------------------------------
# Authoritative regeneration: no ghosts, no accumulation
# --------------------------------------------------------------------
rm -rf "$OUT_STAGE"
mkdir -p "$OUT_STAGE"

changed=0

# --------------------------------------------------------------------
# Render client configs from canonical plan reader
# --------------------------------------------------------------------
while IFS=$'\t' read -r \
	base iface slot dns \
	client_addr4 client_addr6 \
	allowed_client allowed_server \
	endpoint \
	server_addr4 server_addr6 server_routes
do
	[ -n "$base" ]  || die "missing base"
	[ -n "$iface" ] || die "missing iface for base=$base"
	[ -n "$client_addr4" ] || die "missing client_addr4 for $base $iface"
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

	out_dir="$OUT_STAGE/$base"
	mkdir -p "$out_dir"
	out="$out_dir/$iface.conf"

	tmp="$(mktemp "${out}.XXXXXX")"

	{
		echo "# ------------------------------------------------------------------"
		echo "# 🔐 WireGuard client: ${base} / ${iface}"
		echo "#"
		echo "# Show this config:"
		echo "#   make wg-show BASE=${base} IFACE=${iface}"
		echo "#"
		echo "# Show QR code:"
		echo "#   make wg-qr   BASE=${base} IFACE=${iface}"
		echo "# Routing note:"
		echo "#   - Windows: keep 'Table = off' (prevents LAN route precedence)"
		echo "#   - Linux: keep it if explicit routing is enabled"
		echo "#   - Android/iOS: remove it (ignored / unsupported)"
		echo "# ------------------------------------------------------------------"
		if [ "$VERBOSE" -ge 2 ]; then
			echo "#"
			echo "# Plan metadata (documentary only):"
			echo "#   slot           = $slot"
			echo "#   allowed_server = $allowed_server"
			echo "#   server_addr4   = $server_addr4"
			echo "#   server_addr6   = $server_addr6"
			echo "#   server_routes  = $server_routes"
			echo "#   endpoint       = ${WG_ENDPOINT:-$endpoint}"
			echo "#   dns            = ${WG_DNS:-$dns}"
			echo "#   mtu            = ${WG_MTU:-1420} (effective)"
			echo "#   keepalive      = $WG_PERSISTENT_KEEPALIVE"
			echo "#   generated_at   = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
			echo
		fi
		echo "[Interface]"
		echo "PrivateKey = $client_private"
		addr_line=""
		[ -n "$client_addr4" ] && addr_line="$client_addr4"
		[ -n "$client_addr6" ] && addr_line="${addr_line:+$addr_line, }$client_addr6"
		[ -n "$addr_line" ] && echo "Address = $addr_line"
		if [ -n "${WG_DNS:-$dns}" ]; then
			echo "DNS = ${WG_DNS:-$dns}"
		fi
		echo "# Table = off   # Linux-only; uncomment for Windows / server-side routing"
		echo
		echo "[Peer]"
		echo "PublicKey = $server_public"
		echo "AllowedIPs = $allowed_client"
		echo "Endpoint = ${WG_ENDPOINT:-$endpoint}"
		echo "PersistentKeepalive = $WG_PERSISTENT_KEEPALIVE"
	} >"$tmp"

	chmod 600 "$tmp"
	mv -f "$tmp" "$out"
	changed=1
done < <("$PLAN_READER" "$PLAN")

# --------------------------------------------------------------------
# Atomically replace export tree
# --------------------------------------------------------------------
rm -rf "${OUT_ROOT}.prev"
if [ -d "$OUT_ROOT" ]; then
	mv -f "$OUT_ROOT" "${OUT_ROOT}.prev"
fi
mv -f "$OUT_STAGE" "$OUT_ROOT"
rm -rf "${OUT_ROOT}.prev"

if [ "$changed" -eq 0 ]; then
	echo "⚪ no client config changes"
fi
