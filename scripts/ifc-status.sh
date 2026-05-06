#!/bin/sh
set -eu
LC_ALL=C; export LC_ALL

# Usage:
#   ifc-status.sh [ROOT]
#
# ROOT:
#   Base directory to scan (default: /var/lib/homelab)
#
# Read-only. Prints a summary of IFC stamps and object stores.

ROOT="${1:-/var/lib/homelab}"

echo "IFC status for ROOT=$ROOT"
echo

# 1. Count stamps
STAMP_COUNT=$(find "$ROOT" -type f -name '*.installed_hash' 2>/dev/null | wc -l | awk '{print $1}')
echo "Stamps:           $STAMP_COUNT"

# 2. Count objects and total size
OBJ_DIRS=$(find "$ROOT" -type d -name 'objects' 2>/dev/null || true)

OBJ_COUNT=0
OBJ_SIZE=0

if [ -n "$OBJ_DIRS" ]; then
  while IFS= read -r d; do
    c=$(find "$d" -maxdepth 1 -type f 2>/dev/null | wc -l | awk '{print $1}')
    s=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    OBJ_COUNT=$(( OBJ_COUNT + c ))
    OBJ_SIZE=$(( OBJ_SIZE + s ))
  done <<EOF
$OBJ_DIRS
EOF
fi

echo "Objects:          $OBJ_COUNT"
echo "Object size (KB): $OBJ_SIZE"
echo

# 3. Orphan stamps (stamp exists, DST missing)
ORPHAN_STAMPS=0
find "$ROOT" -type f -name '*.installed_hash' 2>/dev/null | while read -r stamp; do
  dst="${stamp%.installed_hash}"
  if [ ! -f "$dst" ]; then
    ORPHAN_STAMPS=$(( ORPHAN_STAMPS + 1 ))
  fi
done

# subshell above, so recompute in a safe way:
ORPHAN_STAMPS=$(find "$ROOT" -type f -name '*.installed_hash' 2>/dev/null | \
  while read -r stamp; do
    dst="${stamp%.installed_hash}"
    [ ! -f "$dst" ] && echo x
  done | wc -l | awk '{print $1}')

echo "Orphan stamps:    $ORPHAN_STAMPS"

# 4. Unreferenced objects (no stamp points to them)
USED_HASHES_FILE="$(mktemp "${ROOT%/}/ifc.used.XXXXXX")"
trap 'rm -f "$USED_HASHES_FILE"' EXIT

find "$ROOT" -type f -name '*.installed_hash' 2>/dev/null | while read -r stamp; do
  obj_hash="$(sed -n '2p' "$stamp" 2>/dev/null || true)"
  [ -n "$obj_hash" ] && printf '%s\n' "$obj_hash" >> "$USED_HASHES_FILE"
done

if [ -s "$USED_HASHES_FILE" ]; then
  sort -u "$USED_HASHES_FILE" -o "$USED_HASHES_FILE"
fi

is_used() {
  h="$1"
  grep -qx "$h" "$USED_HASHES_FILE" 2>/dev/null
}

UNREF_OBJS=0

if [ -n "$OBJ_DIRS" ]; then
  while IFS= read -r d; do
    find "$d" -maxdepth 1 -type f 2>/dev/null | while read -r obj; do
      base="$(basename "$obj")"
      if ! is_used "$base"; then
        echo x
      fi
    done
  done <<EOF
$OBJ_DIRS
EOF
fi | wc -l | awk '{print $1}' | {
  read UNREF_OBJS
  echo "Unreferenced objs: $UNREF_OBJS"
}

echo
echo "Done."
