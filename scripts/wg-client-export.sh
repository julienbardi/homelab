#!/usr/bin/env bash
set -euo pipefail

# wg-client-export.sh — emit client configs from compiled intent (plan.tsv + alloc.csv)
#
# Reads:
#   /volume1/homelab/wireguard/compiled/plan.tsv
#   /volume1/homelab/wireguard/compiled/alloc.csv
#   /etc/wireguard/wgX.pub (server public keys)
#   /etc/wireguard/<base>-<iface>.key (client private keys created by wg-deploy)
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

WG_DIR="/etc/wireguard"
OUT_ROOT="$ROOT/export/clients"

WG_IPV6S="2a01:8b81:4800:9c00:10::1/128 2a01:8b81:4800:9c00:11::1/128 2a01:8b81:4800:9c00:12::1/128 2a01:8b81:4800:9c00:13::1/128 \
		  2a01:8b81:4800:9c00:14::1/128 2a01:8b81:4800:9c00:15::1/128 2a01:8b81:4800:9c00:16::1/128 2a01:8b81:4800:9c00:17::1/128"

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
  awk -F, -v b="$base" '($1==b){print $2; found=1} END{exit found?0:1}' "$ALLOC"
}

# plan.tsv: base iface hostid
while IFS="$(printf '\t')" read -r base iface hid; do
  [ -n "${base:-}" ] || continue
  [ -n "${iface:-}" ] || die "plan.tsv: missing iface for base=$base"
  [ -n "${hid:-}" ]  || die "plan.tsv: missing hostid for base=$base iface=$iface"

  srv="$iface"                   # e.g. wg6
  srv_pub="$WG_DIR/$srv.pub"      # e.g. /etc/wireguard/wg6.pub
  cli_key="$WG_DIR/$base-$srv.key"

  need "$srv_pub"
  need "$cli_key"

  server_public="$(cat "$srv_pub")"
  client_private="$(cat "$cli_key")"

  if ! hostid="$(alloc_lookup "$base")"; then
	die "alloc.csv: no allocation for base=$base"
  fi

  # IPv4 is derived from interface subnet + hostid
  client_ipv4="$(awk -v h="$hostid" -v i="${srv#wg}" '
	BEGIN { printf "10.%d.0.%d/32", 10+i, h }
  ')"

  # IPv6 derived deterministically from hostid for IPv6-capable interfaces
  iface_id="${srv#wg}"
  case "$srv" in
	wg4|wg5|wg6|wg7)
		ipv6_prefix="$(awk -v n=$((iface_id+1)) '{print $n}' <<<"$WG_IPV6S")"
		client_ipv6="$(sed 's/::1$//' <<<"${ipv6_prefix%/*}")::${hostid}/128"
		;;
	*)
		client_ipv6=""
		;;
  esac

  case "$srv" in
	wg0) allowed="10.0.0.0/32" ;;
	wg1) allowed="10.89.12.0/24" ;;
	wg2) allowed="0.0.0.0/0" ;;
	wg3) allowed="10.89.12.0/24, 0.0.0.0/0" ;;
	wg4) allowed="::/0" ;;
	wg5) allowed="10.89.12.0/24, ::/0" ;;
	wg6) allowed="0.0.0.0/0, ::/0" ;;
	wg7) allowed="10.89.12.0/24, 0.0.0.0/0, ::/0" ;;
	*) die "unknown iface $srv" ;;
  esac

  out_dir="$OUT_ROOT/$base"
  mkdir -p "$out_dir"
  out="$out_dir/$srv.conf"

{
	echo "# ${base}-${srv}"
	echo
	echo "[Interface]"
	echo "PrivateKey = $client_private"
	echo "Address = $client_ipv4${client_ipv6:+, $client_ipv6}"
	[ -n "$WG_DNS" ] && echo "DNS = $WG_DNS"
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
	[ -n "$WG_ENDPOINT" ] && echo "Endpoint = $WG_ENDPOINT"
	echo "PersistentKeepalive = $WG_PERSISTENT_KEEPALIVE"
} >"$out"

  chmod 600 "$out"
  echo "wg-client-export: wrote $out"
done <"$PLAN"
