#!/bin/sh
# wg-compile-keys.sh — idempotent client key compiler
set -eu

ROOT="${WG_ROOT:-/volume1/homelab/wireguard}"
PLAN="$ROOT/compiled/plan.tsv"
OUT="$ROOT/compiled/keys.tsv"

umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_IF_CHANGED="$SCRIPT_DIR/install_if_changed.sh"

die() { echo "wg-compile-keys: ERROR: $*" >&2; exit 1; }

[ -x "$INSTALL_IF_CHANGED" ] || die "install_if_changed.sh not found or not executable"
[ -f "$PLAN" ] || die "missing plan.tsv at $PLAN"
command -v wg >/dev/null 2>&1 || die "wg not found in PATH"

EXISTING_KEYS="$OUT"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf "base\tiface\tclient_pub\tclient_priv\n" >"$tmp"

# If keys.tsv doesn't exist yet, treat it as empty (but don't mutate it here).
[ -f "$EXISTING_KEYS" ] || : >"$EXISTING_KEYS"

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
	/^#/ { next }
	/^[[:space:]]*$/ { next }

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

		# Generate new key for new client
		cmd = "wg genkey"
		cmd | getline new_priv
		close(cmd)
		sub(/\r?\n$/, "", new_priv)

		cmd = "echo \"" new_priv "\" | wg pubkey"
		cmd | getline new_pub
		close(cmd)
		sub(/\r?\n$/, "", new_pub)

		print base, iface, new_pub, new_priv
	}
' "$EXISTING_KEYS" "$PLAN" >>"$tmp"

# Hard invariant: header-only output is illegal.
if [ "$(wc -l <"$tmp")" -le 1 ]; then
	die "no keys generated from plan.tsv (plan empty/mismatched, or parsing failed)"
fi

rc=0
"$INSTALL_IF_CHANGED" --quiet "$tmp" "$OUT" root root 600 || rc=$?
case "$rc" in
	0|3) exit 0 ;;
	*)   exit "$rc" ;;
esac
