#!/bin/sh
set -eu
umask 077

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"
OUT_BASE="$WG_ROOT/out/server/base"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_IF_CHANGED="$SCRIPT_DIR/install_if_changed.sh"

[ -x "$INSTALL_IF_CHANGED" ] || {
	echo "wg-ensure-server-keys: ERROR: install_if_changed.sh not found or not executable" >&2
	exit 1
}

[ -f "$PLAN" ] || {
	echo "wg-ensure-server-keys: ERROR: missing $PLAN" >&2
	exit 1
}

mkdir -p "$OUT_BASE"
chmod 700 "$OUT_BASE" 2>/dev/null || true

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

[ -n "$ifaces" ] || {
	echo "wg-ensure-server-keys: ERROR: no ifaces found in $PLAN" >&2
	exit 1
}

for iface in $ifaces; do
	case "$iface" in
		wg[0-9]|wg1[0-5]) ;;
		*)
			echo "wg-ensure-server-keys: ERROR: invalid iface '$iface'" >&2
			exit 1
			;;
	esac

	i="${iface#wg}"
	out="$OUT_BASE/$iface.conf"

	# Ensure semantics: never overwrite existing base config
	[ -f "$out" ] && continue

	tmp="$(mktemp)"
	trap 'rm -f "$tmp"' EXIT

	cat >"$tmp" <<EOF
[Interface]
Address = 10.${i}.0.1/16, fd89:7a3b:42c0:${i}::1/64
ListenPort = $((51420 + i))
PrivateKey = __REPLACED_AT_DEPLOY__
EOF

	case "$iface" in
		wg4|wg7) echo "Table = off" >>"$tmp" ;;
	esac

	"$INSTALL_IF_CHANGED" --quiet "$tmp" "$out" root root 600
done
