#!/usr/bin/env bash
set -euo pipefail

WG_DIR="/etc/wireguard"
ROOT="/volume1/homelab/wireguard"

PLAN="$ROOT/compiled/plan.tsv"
KEYS="$ROOT/compiled/keys.tsv"

WG_BIN="/usr/bin/wg"
WG_QUICK="/usr/bin/wg-quick"

SERVER_KEYS_DIR="$ROOT/server-keys"
CLIENT_KEYDIR="$ROOT/compiled/client-keys"

die()  { echo "wg-deploy: ERROR: $*" >&2; exit 1; }
need() { [ -e "$1" ] || die "missing required path: $1"; }

LOCKFILE="/run/wg-apply.lock"
exec {LOCKFD}>"$LOCKFILE" || die "cannot create lock file $LOCKFILE (must run as root)"
flock -n "$LOCKFD" || die "another wg-apply is already running"

need "$PLAN"
need "$KEYS"
need "$SERVER_KEYS_DIR"

# plan.tsv is strict TSV emitted by wg-compile.sh.
# Columns:
#   1 base
#   2 iface
#   3 slot
#   4 dns
#   5 client_addr4
#   6 client_addr6
#   7 AllowedIPs_client
#   8 AllowedIPs_server
#   9 endpoint
#
# Validate the first non-comment, non-empty line is the expected header.
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
' "$PLAN" || die "plan.tsv: unexpected header (not strict TSV contract)"

mapfile -t ACTIVE_IFACES < <(
	awk -F'\t' '
		/^#/ { next }
		/^[[:space:]]*$/ { next }

		$1=="base" &&
		$2=="iface" &&
		$3=="slot" &&
		$4=="dns" &&
		$5=="client_addr4" &&
		$6=="client_addr6" &&
		$7=="AllowedIPs_client" &&
		$8=="AllowedIPs_server" &&
		$9=="endpoint" { next }

		{ if ($2 != "") print $2 }
	' "$PLAN" | sort -u
)

[ "${#ACTIVE_IFACES[@]}" -gt 0 ] || die "no interfaces found in plan.tsv"

mkdir -p "$CLIENT_KEYDIR"
chmod 700 "$CLIENT_KEYDIR" 2>/dev/null || true

umask 077

PID="$$"
BASE="$(dirname "$WG_DIR")"
NAME="$(basename "$WG_DIR")"

NEW="$BASE/$NAME.new.$PID"
OLD="$BASE/$NAME.old.$PID"

mkdir "$NEW"

client_pub_lookup() {
	local base="$1" iface="$2"
	awk -F'\t' '
		BEGIN { found=0 }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		{
			b=$1; i=$2; pub=$3;
			if (b==B && i==I) { print pub; found=1; exit 0 }
		}
		END { exit(found?0:1) }
	' B="$base" I="$iface" "$KEYS"
}

client_priv_lookup() {
	local base="$1" iface="$2"
	awk -F'\t' '
		BEGIN { found=0 }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		{
			b=$1; i=$2; priv=$4;
			if (b==B && i==I) { print priv; found=1; exit 0 }
		}
		END { exit(found?0:1) }
	' B="$base" I="$iface" "$KEYS"
}

# --------------------------------------------------------------------
# Build server interface configs in NEW/, consuming authoritative server keys
# --------------------------------------------------------------------
for dev in "${ACTIVE_IFACES[@]}"; do
	case "$dev" in
		wg[0-9]|wg1[0-5]) ;;
		*) die "invalid iface '$dev'" ;;
	esac

	i="${dev#wg}"

	port=$((51420 + i))
	ipv4="10.${i}.0.1/16"
	ipv6="2a01:8b81:4800:9c00:${i}::1/128"

	key_src="$SERVER_KEYS_DIR/$dev.key"
	pub_src="$SERVER_KEYS_DIR/$dev.pub"
	need "$key_src"
	need "$pub_src"

	install -m 600 "$key_src" "$NEW/$dev.key"
	install -m 644 "$pub_src" "$NEW/$dev.pub"

	priv="$(tr -d '\r\n' <"$key_src")"

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
done

# --------------------------------------------------------------------
# Append peer stanzas to per-interface configs (strict TSV consumption)
# --------------------------------------------------------------------
awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }

	$1=="base" &&
	$2=="iface" &&
	$3=="slot" &&
	$4=="dns" &&
	$5=="client_addr4" &&
	$6=="client_addr6" &&
	$7=="AllowedIPs_client" &&
	$8=="AllowedIPs_server" &&
	$9=="endpoint" { next }

	{ print $1 "\t" $2 "\t" $8 }
' "$PLAN" | while IFS=$'\t' read -r base iface allowed_srv; do
	conf="$NEW/$iface.conf"
	[ -f "$conf" ] || die "plan.tsv references iface '$iface' but $conf was not generated"

	pub="$(client_pub_lookup "$base" "$iface")" || die "keys.tsv: missing public key for base=$base iface=$iface"
	priv="$(client_priv_lookup "$base" "$iface")" || die "keys.tsv: missing private key for base=$base iface=$iface"

	printf "%s\n" "$priv" >"$CLIENT_KEYDIR/$base-$iface.key"
	chown root:root "$CLIENT_KEYDIR/$base-$iface.key" 2>/dev/null || true
	chmod 600 "$CLIENT_KEYDIR/$base-$iface.key" 2>/dev/null || true

	cat >>"$conf" <<EOF

[Peer]
# $base-$iface
PublicKey = $pub
AllowedIPs = $allowed_srv
EOF
done

# --------------------------------------------------------------------
# Keep-list
# --------------------------------------------------------------------
KEEP="$NEW/keep.list"
: >"$KEEP"

for dev in "${ACTIVE_IFACES[@]}"; do
	echo "$dev.conf" >>"$KEEP"
	echo "$dev.key"  >>"$KEEP"
	echo "$dev.pub"  >>"$KEEP"
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

for dev in "${ACTIVE_IFACES[@]}"; do
	if ip link show "$dev" >/dev/null 2>&1; then
		"$WG_BIN" syncconf "$dev" <("$WG_QUICK" strip "$dev")
	else
		"$WG_QUICK" up "$dev"
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
