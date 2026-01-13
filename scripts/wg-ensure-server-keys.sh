#!/bin/sh
set -eu
umask 077

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"
OUT_BASE="$WG_ROOT/out/server/base"

[ -f "$PLAN" ] || { echo "ERROR: missing $PLAN" >&2; exit 1; }

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

[ -n "$ifaces" ] || { echo "ERROR: no ifaces found in $PLAN" >&2; exit 1; }

for iface in $ifaces; do
	case "$iface" in
		wg[0-9]|wg1[0-5]) ;;
		*) echo "ERROR: invalid iface '$iface'" >&2; exit 1 ;;
	esac

	i="${iface#wg}"

	out="$OUT_BASE/$iface.conf"
	cat >"$out" <<EOF
[Interface]
Address = 10.${i}.0.1/16, 2a01:8b81:4800:9c00:${i}::1/128
ListenPort = $((51420 + i))
PrivateKey = __REPLACED_AT_DEPLOY__
EOF

	case "$iface" in
		wg4|wg7) echo "Table = off" >>"$out" ;;
	esac

	chmod 600 "$out" 2>/dev/null || true
done

echo "server base configs OK: $OUT_BASE"
