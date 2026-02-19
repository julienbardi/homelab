#!/usr/bin/env bash
# wg-compile-keys.sh — idempotent client key compiler
set -eu

# shellcheck disable=SC1091
source /volume1/homelab/homelab.env
: "${WG_ROOT:?WG_ROOT not set}"

PLAN_V2="${WG_ROOT}/compiled/plan.v2.tsv"
export USE_PLAN_V2=1

[ -f "$PLAN_V2" ] || {
	echo "FATAL: plan.v2.tsv is required and missing" >&2
	exit 1
}

if [ "$USE_PLAN_V2" -eq 1 ]; then
	PLAN="$PLAN_V2"
else
	PLAN="$WG_ROOT/compiled/plan.tsv"
fi

OUT="$WG_ROOT/compiled/keys.tsv"

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

# Ensure keys.tsv exists and has a header, so AWK FNR==NR only ever applies to it.
if [ ! -s "$EXISTING_KEYS" ]; then
	printf "base\tiface\tclient_pub\tclient_priv\n" >"$EXISTING_KEYS"
fi

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

	# Skip plan header row (v1 or v2)
	(ENVIRON["USE_PLAN_V2"]=="1" && $1=="node" && $2=="iface" && $3=="profile") { next }
	(ENVIRON["USE_PLAN_V2"]!="1" && $1=="base" && $2=="iface") { next }

	{
		base  = $1
		iface = $2
		key   = base SUBSEP iface

		# In v2, multiple rows per base+iface are expected; only act once
		if (seen[key]++) next

		# Reuse existing key if present
		if (key in priv) {
			print base, iface, pub[key], priv[key]
			next
		}

		# Generate new key for new client
		cmd = "wg genkey"
		if ((cmd | getline new_priv) <= 0) {
			print "wg-compile-keys: ERROR: wg genkey failed" > "/dev/stderr"
			exit 1
		}
		close(cmd)
		sub(/\r?\n$/, "", new_priv)

		cmd = "echo \"" new_priv "\" | wg pubkey"
		if ((cmd | getline new_pub) <= 0) {
			print "wg-compile-keys: ERROR: wg pubkey failed" > "/dev/stderr"
			exit 1
		}
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
