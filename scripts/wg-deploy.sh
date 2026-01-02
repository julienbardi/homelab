#!/bin/sh
set -eu

# wg-deploy.sh — consume compiled plan and atomically deploy WireGuard state
# Inputs (must exist):
#   /volume1/homelab/wireguard/compiled/plan.tsv
#   /volume1/homelab/wireguard/compiled/alloc.csv
#
# Behavior:
# - Renders server + client configs into a staging dir
# - Atomically swaps into /etc/wireguard
# - Applies peers and brings interfaces up
# - Enforces isolation for WAN-only iface (wg6): no client-to-client forwarding
# - DNS for wg6 is served on the WG interface IP (no LAN route needed)
#
# Assumptions:
# - Server keys may already exist; never overwrite existing keys
# - Client keys may already exist; never overwrite existing keys
# - IPv4/IPv6 addressing schemes are fixed and deterministic

WG_DIR="/etc/wireguard"
ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"

WG_BIN="/usr/bin/wg"
WG_QUICK="/usr/bin/wg-quick"

# Interface parameters (must match your established model)
WG_IFACES="0 1 2 3 4 5 6 7"
WG_PORTS="51420 51421 51422 51423 51424 51425 51426 51427"
WG_IPV4S="10.10.0.1/24 10.11.0.1/24 10.12.0.1/24 10.13.0.1/24 10.14.0.1/24 10.15.0.1/24 10.16.0.1/24 10.17.0.1/24"
WG_IPV6S="2a01:8b81:4800:9c00:10::1/128 2a01:8b81:4800:9c00:11::1/128 2a01:8b81:4800:9c00:12::1/128 2a01:8b81:4800:9c00:13::1/128 \
		  2a01:8b81:4800:9c00:14::1/128 2a01:8b81:4800:9c00:15::1/128 2a01:8b81:4800:9c00:16::1/128 2a01:8b81:4800:9c00:17::1/128"

die() { echo "wg-deploy: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

need "$PLAN"
need "$ALLOC"

STAGE="$(mktemp -d "$WG_DIR/.staging.XXXXXX")"
umask 077
trap 'rm -rf "$STAGE"' EXIT INT HUP TERM

# Helper: nth field from space list (1-based)
nth() { echo "$1" | awk -v n="$2" '{print $n}'; }

# Ensure server keys + base configs exist in staging
for i in $WG_IFACES; do
  idx=$((i+1))
  dev="wg$i"
  port="$(nth "$WG_PORTS" "$idx")"
  ipv4="$(nth "$WG_IPV4S" "$idx")"
  ipv6="$(nth "$WG_IPV6S" "$idx")"

  key="$WG_DIR/$dev.key"
  pub="$WG_DIR/$dev.pub"

  if [ ! -f "$key" ] || [ ! -f "$pub" ]; then
	echo "🔑 generating server keys for $dev"
	$WG_BIN genkey | tee "$key" | $WG_BIN pubkey >"$pub"
	chmod 600 "$key" "$pub"
  fi

  priv="$(cat "$key")"
  conf="$STAGE/$dev.conf"
  printf "%s\n%s\n%s\n%s\n" \
	"[Interface]" \
	"Address = $ipv4, $ipv6" \
	"ListenPort = $port" \
	"PrivateKey = $priv" >"$conf"
  chmod 600 "$conf"
done

# Render client peers into server configs
# PLAN columns: base iface hostid
while IFS="$(printf '\t')" read -r base iface hid; do
  [ -n "$base" ] || continue
  dev="$iface"
  conf="$STAGE/$dev.conf"

  # Client keys (never overwrite)
  ckey="$WG_DIR/$base-$iface.key"
  cpub="$WG_DIR/$base-$iface.pub"
  if [ ! -f "$ckey" ] || [ ! -f "$cpub" ]; then
	echo "🔑 generating client keys for $base-$iface"
	$WG_BIN genkey | tee "$ckey" | $WG_BIN pubkey >"$cpub"
	chmod 600 "$ckey" "$cpub"
  fi

  pub="$(cat "$cpub")"

  # AllowedIPs derived strictly from iface profile
  case "$iface" in
	wg0) allowed="10.0.0.0/32" ;; # no access (placeholder)
	wg1) allowed="10.89.12.0/24" ;;
	wg2) allowed="0.0.0.0/0" ;;
	wg3) allowed="10.89.12.0/24, 0.0.0.0/0" ;;
	wg4) allowed="::/0" ;;
	wg5) allowed="10.89.12.0/24, ::/0" ;;
	wg6) allowed="0.0.0.0/0, ::/0" ;; # Swiss TV profile
	wg7) allowed="10.89.12.0/24, 0.0.0.0/0, ::/0" ;;
	*) die "unknown iface $iface" ;;
  esac

  printf "\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n" \
	"$base-$iface" "$pub" "$allowed" >>"$conf"
done <"$PLAN"

# Atomic swap into /etc/wireguard
echo "🚀 deploying WireGuard configs atomically"
for f in "$STAGE"/*.conf; do
  mv -f "$f" "$WG_DIR/$(basename "$f")"
done

# Enforce isolation for wg6 (WAN-only): block client-to-client forwarding
if command -v iptables >/dev/null 2>&1; then
  iptables -C FORWARD -i wg6 -o wg6 -j DROP 2>/dev/null || \
	iptables -A FORWARD -i wg6 -o wg6 -j DROP
fi
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -C FORWARD -i wg6 -o wg6 -j DROP 2>/dev/null || \
	ip6tables -A FORWARD -i wg6 -o wg6 -j DROP
fi

# Bring interfaces up (idempotent)
for i in $WG_IFACES; do
  dev="wg$i"
  if ip link show "$dev" >/dev/null 2>&1; then
	$WG_QUICK down "$dev" >/dev/null 2>&1 || true
  fi
  $WG_QUICK up "$dev" || die "failed to bring up $dev"
done

echo "wg-deploy: OK"
