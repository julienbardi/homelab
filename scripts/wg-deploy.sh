#!/usr/bin/env bash
set -euo pipefail

WG_DIR="/etc/wireguard"
ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
ALLOC="$ROOT/compiled/alloc.csv"

WG_BIN="/usr/bin/wg"
WG_QUICK="/usr/bin/wg-quick"

WG_IFACES="0 1 2 3 4 5 6 7"
WG_PORTS="51420 51421 51422 51423 51424 51425 51426 51427"
WG_IPV4S="10.10.0.1/24 10.11.0.1/24 10.12.0.1/24 10.13.0.1/24 10.14.0.1/24 10.15.0.1/24 10.16.0.1/24 10.17.0.1/24"
WG_IPV6S="2a01:8b81:4800:9c00:10::1/128 2a01:8b81:4800:9c00:11::1/128 2a01:8b81:4800:9c00:12::1/128 2a01:8b81:4800:9c00:13::1/128 \
										2a01:8b81:4800:9c00:14::1/128 2a01:8b81:4800:9c00:15::1/128 2a01:8b81:4800:9c00:16::1/128 2a01:8b81:4800:9c00:17::1/128"

PUBDIR="$ROOT/compiled/server-pubkeys"
CLIENT_KEYDIR="$ROOT/compiled/client-keys"
mkdir -p "$PUBDIR" "$CLIENT_KEYDIR"

die() { echo "wg-deploy: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

LOCKFILE="/run/wg-apply.lock"
exec {LOCKFD}>"$LOCKFILE" || die "cannot create lock file $LOCKFILE (must run as root)"
flock -n "$LOCKFD" || die "another wg-apply is already running"

need "$PLAN"
need "$ALLOC"

umask 077

PID="$$"
BASE="$(dirname "$WG_DIR")"
NAME="$(basename "$WG_DIR")"

NEW="$BASE/$NAME.new.$PID"
OLD="$BASE/$NAME.old.$PID"

mkdir "$NEW"

nth() { echo "$1" | awk -v n="$2" '{print $n}'; }

alloc_lookup() {
	local base="$1"
	awk -F, -v b="$base" 'NR>1 && $1==b {print $2; found=1} END{exit(found?0:1)}' "$ALLOC"
}

for i in $WG_IFACES; do
	idx=$((i+1))
	dev="wg$i"
	port="$(nth "$WG_PORTS" "$idx")"
	ipv4="$(nth "$WG_IPV4S" "$idx")"
	ipv6="$(nth "$WG_IPV6S" "$idx")"

	key="$WG_DIR/$dev.key"
	pub="$WG_DIR/$dev.pub"

	if [ ! -f "$key" ] || [ ! -f "$pub" ]; then
		$WG_BIN genkey | tee "$key" | $WG_BIN pubkey >"$pub"
		chmod 600 "$key" "$pub"
	fi

	priv="$(cat "$key")"

	cat >"$NEW/$dev.conf" <<EOF
[Interface]
Address = $ipv4, $ipv6
ListenPort = $port
PrivateKey = $priv
EOF

	case "$dev" in
		wg4|wg7) echo "Table = off" >>"$NEW/$dev.conf" ;;
	esac

	chmod 600 "$NEW/$dev.conf"

	install -m 644 "$pub" "$PUBDIR/$dev.pub"
done

while IFS=$' \t' read -r base iface hid dns allowed endpoint; do
	[ -n "$base" ] || continue
	[[ "$base" == \#* ]] && continue
	[ "$base" = "base" ] && continue

	conf="$NEW/$iface.conf"

	ckey="$WG_DIR/$base-$iface.key"
	cpub="$WG_DIR/$base-$iface.pub"

	if [ ! -f "$ckey" ] || [ ! -f "$cpub" ]; then
		$WG_BIN genkey | tee "$ckey" | $WG_BIN pubkey >"$cpub"
		chmod 600 "$ckey" "$cpub"
	fi

	# Export client private keys for client config generation on the NAS
	install -m 640 "$ckey" "$CLIENT_KEYDIR/$(basename "$ckey")"

	pub="$(cat "$cpub")"

	hostid="$(alloc_lookup "$base")" || die "alloc.csv: no allocation for base=$base"

	ifnum="${iface#wg}"
	peer_v4="$(awk -v h="$hostid" -v i="$ifnum" 'BEGIN{printf "10.%d.0.%d/32", 10+i, h}')"
	peer_v6="$(awk -v h="$hostid" -v i="$ifnum" 'BEGIN{printf "2a01:8b81:4800:9c00:%d::%d/128", 10+i, h}')"

	# NOTE FOR OPERATORS:
	# -------------------
	# On the SERVER, AllowedIPs defines which source IPs are accepted from a peer
	# and which routes are installed *towards* that peer.
	#
	# It MUST contain ONLY the peer's tunnel IP (/32, /128).
	#
	# Full-tunnel routing (0.0.0.0/0, ::/0) belongs ONLY on the CLIENT.
	# Putting 0.0.0.0/0 here will break routing for all peers.
	cat >>"$conf" <<EOF

[Peer]
# $base-$iface
PublicKey = $pub
AllowedIPs = $peer_v4, $peer_v6
EOF
done <"$PLAN"

KEEP="$NEW/keep.list"
: >"$KEEP"

for i in $WG_IFACES; do
	echo "wg$i.conf" >>"$KEEP"
	echo "wg$i.key"  >>"$KEEP"
	echo "wg$i.pub"  >>"$KEEP"
done

while IFS=$' \t' read -r base iface hid dns allowed endpoint; do
	[ -n "$base" ] || continue
	[[ "$base" == \#* ]] && continue
	[ "$base" = "base" ] && continue

	echo "$base-$iface.key" >>"$KEEP"
	echo "$base-$iface.pub" >>"$KEEP"
done <"$PLAN"

for f in "$WG_DIR"/*.key "$WG_DIR"/*.pub; do
	[ -f "$f" ] || continue
	cp -a "$f" "$NEW/"
done

echo "🚀 deploying WireGuard configs atomically"

mv "$WG_DIR" "$OLD"
mv "$NEW" "$WG_DIR"

KEEP="$WG_DIR/keep.list"

LEGACY="$WG_DIR/.legacy"
mkdir -p "$LEGACY"
chmod 700 "$LEGACY"

for f in "$OLD"/*; do
	[ -f "$f" ] || continue
	b="$(basename "$f")"
	grep -qx "$b" "$KEEP" || mv "$f" "$LEGACY/"
done

rm -rf "$OLD"

for i in $WG_IFACES; do
	dev="wg$i"
	if ip link show "$dev" >/dev/null 2>&1; then
		$WG_BIN syncconf "$dev" <($WG_QUICK strip "$dev")
	else
		$WG_QUICK up "$dev"
	fi
done

if command -v iptables >/dev/null 2>&1; then
	iptables -C FORWARD -i wg6 -o wg6 -j DROP 2>/dev/null || \
	iptables -A FORWARD -i wg6 -o wg6 -j DROP
fi

if command -v ip6tables >/dev/null 2>&1; then
	ip6tables -C FORWARD -i wg6 -o wg6 -j DROP 2>/dev/null || \
	ip6tables -A FORWARD -i wg6 -o wg6 -j DROP
fi

echo "wg-deploy: OK"
