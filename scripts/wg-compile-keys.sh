#!/bin/sh
# wg-compile-keys.sh
set -eu

ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
OUT="$ROOT/compiled/keys.tsv"

umask 077

[ -f "$PLAN" ] || {
	echo "wg-compile-keys: ERROR: missing plan.tsv" >&2
	exit 1
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf "base\tiface\tclient_pub\tclient_priv\n" >"$tmp"

awk '
	/^#/ { next }
	/^[[:space:]]*$/ { next }

	{
		base  = $1
		iface = $2

		key = base SUBSEP iface
		if (seen[key]++) {
			printf "wg-compile-keys: ERROR: duplicate base+iface %s %s\n", base, iface > "/dev/stderr"
			exit 1
		}

		cmd = "wg genkey"
		cmd | getline priv
		close(cmd)

		cmd = "printf \"%s\" \"" priv "\" | wg pubkey"
		cmd | getline pub
		close(cmd)

		printf "%s\t%s\t%s\t%s\n", base, iface, pub, priv
	}
' "$PLAN" >>"$tmp"

mv -f "$tmp" "$OUT"
chmod 600 "$OUT"

echo "wg-compile-keys: OK"
echo "  keys: $OUT"
