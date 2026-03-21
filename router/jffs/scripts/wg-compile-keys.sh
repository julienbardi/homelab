#!/bin/sh
set -eu; umask 077

# Implements the contracts defined in contracts.inc.
# Any deviation is a bug.

readonly IN_ALLOC="alloc.tsv"
readonly OUT_KEYS="keys.tsv"
readonly KEY_ROOT="/jffs/scripts/wireguard/keys"
readonly ALLOC_HEADER="base	iface	addr	cidr"

: "${WG_DUMP:=0}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

fatal() {
	echo "❌ $*" >&2
	exit 1
}

check_tsv_field() {
	case "$1" in
		*"$'\t'"*|*"$'\n'"*|*"$'\r'"*|*"$'\0'"*)
			fatal "Forbidden character in TSV field: [$1]"
			;;
	esac
}

emit_row() {
	for field in "$@"; do
		check_tsv_field "$field"
	done
	printf '%s\t' "$@" | $SED 's/\t$//'
	printf '\n'
}

# -----------------------------------------------------------------------------
# Preconditions
# -----------------------------------------------------------------------------

[ -f "$IN_ALLOC" ] || fatal "Missing input file: $IN_ALLOC"

WG="/usr/sbin/wg"   # adjust if your router uses a different absolute path

AWK="busybox awk"
SORT="busybox sort"
UNIQ="busybox uniq"
WC="busybox wc"
SED="busybox sed"

"$WG" --help >/dev/null 2>&1 || fatal "wg not available at $WG"
busybox awk 'BEGIN{exit 0}' </dev/null || fatal "busybox awk not available"
busybox sort </dev/null >/dev/null 2>&1 || fatal "busybox sort not available"
busybox uniq </dev/null >/dev/null 2>&1 || fatal "busybox uniq not available"
busybox wc </dev/null >/dev/null 2>&1 || fatal "busybox wc not available"

mkdir -p "$KEY_ROOT"
chmod 700 "$KEY_ROOT"

# -----------------------------------------------------------------------------
# Generate keys idempotently
# -----------------------------------------------------------------------------

tmp_keys="/tmp/wg-keys.$$"
: >"$tmp_keys"
trap 'rm -f "$tmp_keys"' EXIT

$AWK -F'\t' '
	NR>1 { print $1 "\t" $2 }
' "$IN_ALLOC" | LC_ALL=C $SORT | $UNIQ -d | \
while read -r dup; do
	fatal "Duplicate base/iface pair in alloc.tsv: $dup"
done || fatal "alloc.tsv contains duplicate base/iface pairs"


$AWK -F'\t' -v header="$ALLOC_HEADER" '
	NR==1 {
		if ($0 != header)
			exit 2
	}
	NR>1 {
		if (NF < 2 || $1=="" || $2=="")
			exit 3
		print $1 "\t" $2
	}
' "$IN_ALLOC" | LC_ALL=C $SORT -u | while IFS="$(printf '\t')" read -r base iface; do
	dir="$KEY_ROOT/$iface"
	key="$dir/$base.key"

	mkdir -p "$dir"

	if [ ! -f "$key" ]; then
		"$WG" genkey >"$key"
		chmod 600 "$key"
	fi

	pub="$("$WG" pubkey <"$key")"
	printf '%s\t%s\t%s\n' "$base" "$iface" "$pub" >>"$tmp_keys"
done || fatal "alloc.tsv malformed (bad header or missing base/iface)"

# -----------------------------------------------------------------------------
# Emit keys.tsv (optional)
# -----------------------------------------------------------------------------

if [ "$WG_DUMP" -eq 1 ]; then
	out_tmp="/tmp/wg-keys-out.$$"
	: >"$out_tmp"
	trap 'rm -f "$tmp_keys" "$out_tmp"' EXIT
	{
		emit_row base iface pubkey
		LC_ALL=C $SORT "$tmp_keys" | while IFS="$(printf '\t')" read -r base iface pub; do
			emit_row "$base" "$iface" "$pub"
		done
	} >"$out_tmp"

	mv -f "$out_tmp" "$OUT_KEYS"
	echo "✅ Generated $OUT_KEYS"
	count="$($WC -l <"$tmp_keys")"
	echo "ℹ️  Generated $count WireGuard key(s)"
else
	echo "ℹ️  WG_DUMP=0 — keys.tsv not written"
fi
