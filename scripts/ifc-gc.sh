#!/bin/sh
set -eu
LC_ALL=C; export LC_ALL

ROOT="${1:-/var/lib/homelab}"
TTL="${2:-0}"
now=$(date +%s)

# 1. Remove orphaned stamp files (no corresponding DST)
find "$ROOT" -type f -name '*.installed_hash' | while read -r stamp; do
    dst="${stamp%.installed_hash}"
    if [ ! -f "$dst" ]; then
        rm -f "$stamp"
    fi
done || true

# 2. Build set of referenced object hashes (from second line of stamps)
USED_HASHES_FILE="$(mktemp "${ROOT%/}/ifc.used.XXXXXX")"
trap 'rm -f "$USED_HASHES_FILE"' EXIT

find "$ROOT" -type f -name '*.installed_hash' | while read -r stamp; do
    obj_hash="$(sed -n '2p' "$stamp" 2>/dev/null || true)"
    [ -n "$obj_hash" ] && printf '%s\n' "$obj_hash" >> "$USED_HASHES_FILE"
done || true

[ -s "$USED_HASHES_FILE" ] && sort -u "$USED_HASHES_FILE" -o "$USED_HASHES_FILE"

is_used() {
    grep -qx "$1" "$USED_HASHES_FILE" 2>/dev/null
}

# 3. Remove unreferenced objects
find "$ROOT" -type d -name 'objects' 2>/dev/null || true | while read -r obj_root; do
    find "$obj_root" -maxdepth 1 -type f 2>/dev/null || true | while read -r obj; do
        [ -z "$obj" ] && continue
        base="$(basename "$obj")"
        if ! is_used "$base"; then
            if [ "$TTL" -eq 0 ]; then
                rm -f "$obj"
            else
                mtime=$(stat -c %Y "$obj" 2>/dev/null || printf '0')
                age=$(( now - mtime ))
                [ "$age" -gt "$TTL" ] && rm -f "$obj"
            fi
        fi
    done
done

# 4. Remove abandoned IFC workdirs older than 1 day
find "$ROOT" -maxdepth 1 -type d -name 'ifc.*' -mtime +1 -exec rm -rf {} +
