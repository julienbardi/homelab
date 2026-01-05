#!/bin/sh
# wg-compile-keys.sh — idempotent client key compiler
set -eu

ROOT="/volume1/homelab/wireguard"
PLAN="$ROOT/compiled/plan.tsv"
OUT="$ROOT/compiled/keys.tsv"

umask 077

[ -f "$PLAN" ] || {
	echo "wg-compile-keys: ERROR: missing plan.tsv" >&2
	exit 1
}

EXISTING_KEYS="$OUT"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf "base\tiface\tclient_pub\tclient_priv\n" >"$tmp"

awk -F'\t' '
	BEGIN { OFS="\t" }

	# ------------------------------------------------------------
	# Load existing keys.tsv (if present)
	# ------------------------------------------------------------
	FNR==NR {
		if ($1=="base" && $2=="iface") next
		key = $1 SUBSEP $2
		pub[key]  = $3
		priv[key] = $4
		next
	}

	# ------------------------------------------------------------
	# Process plan.tsv
	# ------------------------------------------------------------
	/^#/ || /^[[:space:]]*$/ { next }

	# Skip plan.tsv header row
	$1=="base" && $2=="iface" { next }

	{
		base  = $1
		iface = $2
		key   = base SUBSEP iface

		if (seen[key]++) {
			printf "wg-compile-keys: ERROR: duplicate base+iface %s %s\n", base, iface > "/dev/stderr"
			exit 1
		}

		# Reuse existing key if present
		if (key in priv) {
			print base, iface, pub[key], priv[key]
			next
		}

		# Generate new key ONLY for new client
		cmd = "wg genkey"
		cmd | getline new_priv
		close(cmd)

		cmd = "printf \"%s\" \"" new_priv "\" | wg pubkey"
		cmd | getline new_pub
		close(cmd)

		print base, iface, new_pub, new_priv
	}
' "$EXISTING_KEYS" "$PLAN" >>"$tmp"

mv -f "$tmp" "$OUT"
chmod 600 "$OUT"

echo "wg-compile-keys: OK"
echo "  keys: $OUT"
