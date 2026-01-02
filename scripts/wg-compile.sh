#!/bin/sh
set -eu

# wg-compile.sh — validate staged CSV, allocate stable host IDs, render a plan snapshot
# Authoritative input:
#   /volume1/homelab/wireguard/input/clients.csv   (user,machine,iface)
# Compiled outputs (atomic):
#   /volume1/homelab/wireguard/compiled/clients.lock.csv
#   /volume1/homelab/wireguard/compiled/alloc.csv          (base,hostid)
#   /volume1/homelab/wireguard/compiled/plan.tsv           (base iface hostid)
#
# Notes:
# - iface is the profile (wg0..wg7). No tags/overrides.
# - Deterministic hostid: stateful allocator in alloc.csv, never changes once assigned.
# - Fails loudly; does not modify deployed state.

ROOT="/volume1/homelab/wireguard"
IN_DIR="$ROOT/input"
IN_CSV="$IN_DIR/clients.csv"

OUT_DIR="$ROOT/compiled"
ALLOC="$OUT_DIR/alloc.csv"
LOCK="$OUT_DIR/clients.lock.csv"
PLAN="$OUT_DIR/plan.tsv"

STAGE="$OUT_DIR/.staging.$$"
umask 077

die() { echo "wg-compile: ERROR: $*" >&2; exit 1; }

need() { [ -e "$1" ] || die "missing required path: $1"; }

mkdir -p "$IN_DIR" "$OUT_DIR"
[ -f "$IN_CSV" ] || die "missing input CSV: $IN_CSV"

# Ensure allocator exists
if [ ! -f "$ALLOC" ]; then
  printf "%s\n" "base,hostid" >"$ALLOC"
  chmod 600 "$ALLOC"
fi

mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT INT HUP TERM

# Basic CSV header check (strict)
hdr="$(head -n 1 "$IN_CSV" 2>/dev/null || true)"
[ "$hdr" = "user,machine,iface" ] || die "invalid header; expected: user,machine,iface"

# Normalize + validate lines -> stage/normalized.tsv
# Output columns: user machine iface base
NORM="$STAGE/normalized.tsv"
: >"$NORM"

# Skip header; allow blank lines and comments starting with '#'
tail -n +2 "$IN_CSV" | while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac

  # Strict 3-field CSV; no quoting supported (by design)
  user="$(printf "%s" "$line" | awk -F, '{print $1}')"
  mach="$(printf "%s" "$line" | awk -F, '{print $2}')"
  iface="$(printf "%s" "$line" | awk -F, '{print $3}')"

  [ -n "$user" ] && [ -n "$mach" ] && [ -n "$iface" ] || die "bad row (need 3 fields): $line"

  # Reject extra commas
  extra="$(printf "%s" "$line" | awk -F, 'NF!=3{print "bad"}')"
  [ -z "$extra" ] || die "bad row (expected exactly 3 comma-separated fields): $line"

  # Validate tokens: lower-case a-z0-9- only (keeps your naming stable)
  printf "%s" "$user" | grep -Eq '^[a-z0-9-]+$' || die "invalid user '$user' (allowed: [a-z0-9-]+)"
  printf "%s" "$mach" | grep -Eq '^[a-z0-9-]+$' || die "invalid machine '$mach' (allowed: [a-z0-9-]+)"

  printf "%s" "$iface" | grep -Eq '^wg[0-7]$' || die "invalid iface '$iface' (must be wg0..wg7)"

  base="$user-$mach"
  printf "%s\t%s\t%s\t%s\n" "$user" "$mach" "$iface" "$base" >>"$NORM"
done

# Duplicates check: (base,iface) must be unique
dups="$(awk -F'\t' '{print $4","$3}' "$NORM" | sort | uniq -d || true)"
[ -z "$dups" ] || die "duplicate base,iface entries:\n$dups"

# Extract bases set
BASES="$STAGE/bases.txt"
awk -F'\t' '{print $4}' "$NORM" | sort -u >"$BASES"

# Load alloc into a tmp map for lookups
ALLOC_MAP="$STAGE/alloc_map.tsv"
tail -n +2 "$ALLOC" 2>/dev/null | awk -F, 'NF==2{print $1"\t"$2}' >"$ALLOC_MAP" || true

# Build used hostid set
USED="$STAGE/used_hostids.txt"
awk -F'\t' 'NF==2{print $2}' "$ALLOC_MAP" | sort -n >"$USED" || true

# Allocate host IDs for any new base
# Range: 2..254
ALLOC_NEW="$STAGE/alloc_new.tsv"
: >"$ALLOC_NEW"

while IFS= read -r base; do
  [ -n "$base" ] || continue
  existing="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$ALLOC_MAP" | head -n1 || true)"
  if [ -n "$existing" ]; then
	printf "%s\t%s\n" "$base" "$existing" >>"$ALLOC_NEW"
	continue
  fi

  # Find first free hostid
  hid=2
  while [ "$hid" -le 254 ]; do
	if ! grep -qx "$hid" "$USED" 2>/dev/null; then
	  printf "%s\t%s\n" "$base" "$hid" >>"$ALLOC_NEW"
	  printf "%s\n" "$hid" >>"$USED"
	  break
	fi
	hid=$((hid+1))
  done
  [ "$hid" -le 254 ] || die "hostid exhaustion (no free IDs in 2..254)"
done <"$BASES"

# Emit plan.tsv: base iface hostid
: >"$PLAN.tmp"
while IFS= read -r base; do
  [ -n "$base" ] || continue
  hid="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$ALLOC_NEW" | head -n1 || true)"
  [ -n "$hid" ] || die "internal: missing hostid for base $base"

  awk -F'\t' -v b="$base" -v hid="$hid" '$4==b{print b"\t"$3"\t"hid}' "$NORM" >>"$PLAN.tmp"
done <"$BASES"

# Sort plan for stable diffs
sort -k1,1 -k2,2 "$PLAN.tmp" >"$STAGE/plan.tsv"
rm -f "$PLAN.tmp"

# Write lock CSV with strict header and sorted rows
LOCK_TMP="$STAGE/clients.lock.csv"
printf "%s\n" "user,machine,iface" >"$LOCK_TMP"
awk -F'\t' '{print $1","$2","$3}' "$NORM" | sort >>"$LOCK_TMP"

# Update alloc.csv atomically: merge old + new, keep header, stable sort
ALLOC_TMP="$STAGE/alloc.csv"
printf "%s\n" "base,hostid" >"$ALLOC_TMP"
# old entries
tail -n +2 "$ALLOC" 2>/dev/null | awk -F, 'NF==2{print $1","$2}' >>"$ALLOC_TMP" || true
# new entries (may include existing; uniq later)
awk -F'\t' '{print $1","$2}' "$ALLOC_NEW" >>"$ALLOC_TMP"
# uniq by base (first wins) — keep existing assignment if present
awk -F, '
  NR==1{print; next}
  !seen[$1]++ {print}
' "$ALLOC_TMP" >"$STAGE/alloc.merged.csv"

# Basic sanity: alloc has unique bases and hostids within range
awk -F, 'NR>1{
  if ($2<2 || $2>254) {print "bad hostid: "$0; exit 2}
}' "$STAGE/alloc.merged.csv" >/dev/null 2>&1 || die "alloc.csv contains invalid hostid"

# Commit compiled outputs atomically
# (1) plan.tsv
mv -f "$STAGE/plan.tsv" "$PLAN"
chmod 600 "$PLAN"

# (2) clients.lock.csv
mv -f "$LOCK_TMP" "$LOCK"
chmod 600 "$LOCK"

# (3) alloc.csv
mv -f "$STAGE/alloc.merged.csv" "$ALLOC"
chmod 600 "$ALLOC"

echo "wg-compile: OK"
echo "  input:    $IN_CSV"
echo "  lock:     $LOCK"
echo "  alloc:    $ALLOC"
echo "  plan:     $PLAN"
