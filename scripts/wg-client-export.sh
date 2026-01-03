#!/usr/bin/env bash
set -euo pipefail

# wg-client-export.sh — emit client configs from compiled intent (plan.tsv + alloc.csv)
#
# Reads:
#   /volume1/homelab/wireguard/compiled/plan.tsv
#   /volume1/homelab/wireguard/compiled/alloc.csv
#   /volume1/homelab/wireguard/compiled/server-pubkeys/wgX.pub
#   /volume1/homelab/wireguard/compiled/client-keys/<base>-<iface>.key
#
# Writes (default):
#   /volume1/homelab/wireguard/export/clients/<base>/<iface>.conf
#
# Notes:
# - This script does NOT modify /etc/wireguard.
# - It fails loud if required artifacts are missing.
# - Endpoint and DNS are parameterized via environment variables.

ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"

WG_PUBDIR="$ROOT/compiled/server-pubkeys"
WG_KEYDIR="$ROOT/compiled/client-keys"
OUT_ROOT="$ROOT/export/clients"

die() { echo "wg-client-export: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

need "$PLAN"
need "$ALLOC"

# Configurable defaults (override via environment)
WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_DNS="${WG_DNS:-}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"

mkdir -p "$OUT_ROOT"
umask 077

# alloc.csv: base,hostid
alloc_lookup() {
  local base="$1"
  awk -F, -v b="$base" 'NR>1 && ($1==b){print $2; found=1} END{exit found?0:1}' "$ALLOC"
}

# plan.tsv: base iface hostid dns allowed endpoint
while read -r base iface hid dns allowed endpoint; do

  [[ -z "${base:-}" || "$base" == \#* || "$base" == "base" ]] && continue

  [ -n "${iface:-}" ] || die "plan.tsv: missing iface for base=$base"
  [ -n "${hid:-}" ]  || die "plan.tsv: missing hostid for base=$base iface=$iface"

  [ -n "${WG_ENDPOINT:-$endpoint}" ] || die "no endpoint available for $base $iface"

  srv="$iface"
  srv_pub="$WG_PUBDIR/$srv.pub"
  cli_key="$WG_KEYDIR/$base-$srv.key"

  need "$srv_pub"
  need "$cli_key"

  server_public="$(tr -d '\r\n' <"$srv_pub")"
  client_private="$(tr -d '\r\n' <"$cli_key")"

  if ! hostid="$(alloc_lookup "$base")"; then
	die "alloc.csv: no allocation for base=$base"
  fi

  # IPv4 is derived from interface subnet + hostid
  client_ipv4="$(awk -v h="$hostid" -v i="${srv#wg}" '
	BEGIN { printf "10.%d.0.%d/32", 10+i, h }
  ')"

  out_dir="$OUT_ROOT/$base"
  mkdir -p "$out_dir"
  out="$out_dir/$srv.conf"

{
	echo "# ${base}-${srv}"
	echo
	echo "[Interface]"
	echo "PrivateKey = $client_private"
	echo "Address = $client_ipv4"
	echo "DNS = ${WG_DNS:-$dns}"
	echo
	echo "# DNS options:"
	echo "#   - Leave unset to use local / ISP / mobile DNS (often fastest)"
	echo "#   - Optional internal DNS for LAN names: 192.168.50.1"
	echo "#   - Advanced users may configure split DNS on their OS"
	echo
	echo "# Endpoint options for $srv:"
	echo "#   1) WAN / mobile: vpn.bardi.ch:51427"
	echo "#   2) LAN shortcut: 10.89.12.4:51427 or 2a01:8b81:4800:9c00::4"
	echo "#   3) VM on NAS: 127.0.0.1 or ::1"
	echo
	echo "[Peer]"
	echo "PublicKey = $server_public"
	echo "AllowedIPs = $allowed"
	echo "Endpoint = ${WG_ENDPOINT:-$endpoint}"
	echo "PersistentKeepalive = $WG_PERSISTENT_KEEPALIVE"
} >"$out"

  chmod 600 "$out"
  echo "wg-client-export: wrote $out"
done <"$PLAN"
