#!/bin/sh
set -eu
umask 077

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"
SERVER_KEYS_DIR="$WG_ROOT/server-keys"
COMPILED_PUBDIR="$WG_ROOT/compiled/server-pubkeys"

[ -f "$PLAN" ] || { echo "ERROR: missing $PLAN" >&2; exit 1; }
command -v wg >/dev/null 2>&1 || { echo "ERROR: wg not found in PATH" >&2; exit 1; }

mkdir -p "$SERVER_KEYS_DIR" "$COMPILED_PUBDIR"
chmod 700 "$SERVER_KEYS_DIR" 2>/dev/null || true
chmod 2770 "$COMPILED_PUBDIR" 2>/dev/null || true

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
		wg[0-9]|wg1[0-5]) : ;;
		*)
			echo "ERROR: invalid iface '$iface' in plan.tsv" >&2
			exit 1
			;;
	esac

	priv="$SERVER_KEYS_DIR/$iface.key"
	pub="$SERVER_KEYS_DIR/$iface.pub"
	out_pub="$COMPILED_PUBDIR/$iface.pub"

	if [ -f "$priv" ] && [ -f "$pub" ]; then
		cp -f "$pub" "$out_pub"
		chmod 644 "$out_pub" 2>/dev/null || true
		continue
	fi

	if [ -f "$priv" ] && [ ! -f "$pub" ]; then
		wg pubkey <"$priv" >"$pub"
		chmod 600 "$priv" "$pub" 2>/dev/null || true
		cp -f "$pub" "$out_pub"
		chmod 644 "$out_pub" 2>/dev/null || true
		continue
	fi

	if [ ! -f "$priv" ] && [ -f "$pub" ]; then
		echo "ERROR: found $pub but missing $priv (refusing to proceed)" >&2
		exit 1
	fi

	tmp="$priv.tmp.$$"
	wg genkey >"$tmp"
	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$priv"
	wg pubkey <"$priv" >"$pub"
	chmod 600 "$priv" "$pub" 2>/dev/null || true
	cp -f "$pub" "$out_pub"
	chmod 644 "$out_pub" 2>/dev/null || true
done

echo "server keys OK: $SERVER_KEYS_DIR"
